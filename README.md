# AddAllPermissionsToPermissionSet
A Salesforce Apex script that will add permissions to all objects, fields, Tabs, Apex classes, Apex pages, Custom Apps, and Record Types to a given Permission set.

## Summary / Purpose
Takes a Permission Set and applies all permissions to all objects and all fields, or a list of specified objects and all fields on those objects. Also adds permissions to Tabs, Apex classes, Apex pages, Custom Apps, and Record Types. Intended to aid organizations who want to give users such as Admins maximum control over data in the system without using the System Administrator Profile.

This will add to a given Permission Set:
* Read, and View All to all objects and Platform Events, and optionally Write, Delete, and Modify All. You can exclude objects individually or by namespace.
* Read access to all fields on all objects, and optionally edit access. It is aware of certain types like Formulas and does not try to apply write permissions if it's not possible.
* Assigns all Record Types for all Objects.
* Sets the Tab to Visible for all Objects if a Tab exists.
* Assigns all Apex Classes.
* Assigns all Apex Pages.
* Assigns all Custom Apps.

## tl;dr / I Just Want to Run This Thing / Instructions for Admins and Nontechnical People
A few easy steps to run this on all your objects. You need to do this while logged in as a user with the System Administrator profile.

1. Clone your Permission Set.
1. In Developer Console, File -> New -> Apex Class. Name it this, exactly:      `UpdatePSAllFieldsAllObjectsQueueable` and save.
2. In execute anonymous, execute the following two lines, substituting the ID of the Permission Set you want to build -- *strongly recommended* you use the clone -- and whether you want to enable write access in the PS.
```
UpdatePSAllFieldsAllObjectsQueueable aaq = new UpdatePSAllFieldsAllObjectsQueueable([ID OF YOUR PERMISSION SET IN SINGLE QUOTES],[WHETHER YOU WANT TO ENABLE WRITE PERMISSIONS: 'true' OR 'false']);
System.enqueueJob(aaq); 
```

The 15-character ID of your `PermissionSet` is in the URL when you look at it in Setup. It begins with `0PS` and ends before the `%3F`.
```
https://myorg.sandbox.lightning.force.com/lightning/setup/PermSets/page?address=%2F0PSWL0000006Fu1%3Fs%3DEntityPermissions
                                                                                   ^^^^^^^^^^^^^^^
```

If you go to Setup -> Apex Jobs, you will see the status. If your `PermissionSet` is large to begin with, you might get a timeout, in which case you should just trigger it again.
```
IO Exception: Read timed out	
```

After a while, you might find that there is an error. These are usually due to you not having permission to a certain object. For example,
```
Error occured processing component Modify_All. In field: recordType - no RecordType named innohub__Activity__c.Activity_Type_1 found (INVALID_CROSS_REFERENCE_KEY).
```
In this case, it shows that the record type process failed to apply Record Type `Activity_Type_1` on object `innohub__Activity__c`. Either exclude the object altogether, or make sure you have permission to it. Which brings me to...

## Important Caveat

*Make sure you have licenses assigned:* If the running user does not have a license to see a given Object, permissions will not be assigned. For example, Omnichannel, Knowledge, or 3rd party apps.  This may cause errors applying Apex Class, Apex Page, Record Types, or Custom Apps, but will not cause errors in objects or fields.

## How It Works

This process runs in two parts, since some Permission Set configuration can be set in regular Apex, and others have to go through the Metadata API.

Sequence:
1. Step 1 uses Metadata API to query the Permission Set as it exists at the beginning. It then calls itself, passing an `Instruction` for the next step.
2. Step 2 adds Apex Class permission to the local copy of the PermissionSet via a PermissionSet_x record.
3. Step 3 adds Apex Page permission to the local copy of the PermissionSet via a PermissionSet_x record.
4. Step 4 adds Custom App permission to the local copy of the PermissionSet via a PermissionSet_x record.
5. Step 5 adds Record Types to the local copy of the PermissionSet via a PermissionSet_x record.
6. Step 6 updates the Permission Set with the updates so far via the Metadata API.
7. At this point, the system is done updating the PS via the Metadata API, and will now go through objects and fields, applying permission and Tab access.
8. System calls itself with the first batch of Objects to process.

## Part I: Metadata API Process
The `PermissionSet` object contains sub-structures such as `applicationVisibilities` that are not available via regular Apex, necessitationg using the Metadata API. This part uses modified processes from the legendary [apex-mdapi](https://github.com/certinia/apex-mdapi) library. 

The code contains Apex versions of the metadata objects using a `_x` suffix to follow longstanding `json2apex` convention. In this way, each object is modeled using its own "shadow" Apex Class. For example, the aforementioned `applicationVisibilities` is a List of `PermissionSetApplicationVisibility` objects. This system maintains a version of `PermissionSetApplicationVisibility` called `PermissionSetApplicationVisibility_x`.

## Part II: Apex Process

This would seem like a natural fit for `Batchable`. But because the process uses the `EntityDefinition` table to determine the list of objects, we run into a few limitations.
1. `EntityDefinition` does not support `queryMore()`, meaning you can't use it in the source query in a `Batchable`.
2. `EntityDefinition` can not be queried in the body of a `Batchable`.
3. `EntityDefinition` does not support disjunctive queries, meaning we can't use `OR`.
4. `EntityDefinition` will return a maximum of 2000 records.

Also, you can only have 50 `Queueable`s created from a single process; so this process chains itself rather than spawning a bunch of `Queueables` from a single controlling process.

The process keeps two key variables: `Iteration` and `RecordsPerQueueable`. In each iteration it will process the number of Objects specified by `RecordsPerQueueable`, and the query is `OFFSET` by `RecordsPerQueueable` * `Iteration`. If you start on `Iteration` 0 and set `RecordsPerQueueable` to 10, the first time through, the `EntityDefinition` query will be `OFFSET` by 0 * 10 = 0 records, and `LIMIT` 10. This will return the first 10 `EntityDefinition` records.  Once processing is complete, it kicks off a new `Queueable` instance of itself with `Iteration` + 1, so the second time it will `OFFSET` 10 and `LIMIT` 10, returning the second 10 records. It continues until the query doesn't return any more records.

The scope is all objects where `IsCustomizable` is `true` in `EntityDefinition`, and all Platform Events. Because `EntityDefinition` doesn't support `OR` queries, the easiest way to implement this was to explicitly exclude all the Object suffixes we didn't want, like `__Share`. The base query is in `getBaseEntityDefinitionQuery()`. The limitation on `OR` queries forces some filtering when the `EntityDefinition` results are translated to a simple `List` of `String`s.

There is a data structure called `PermissionPackage` that maintains the information about each Object. It has a `ObjectPermissions` record, and `FieldPermissions` records stored in a Map with the field name as key. For each Object, it goes through the following:

1. Query `ObjectPermissions` for the Object, and if it exists, populates it into the `PermissionPackage`.
2. Query `FieldPermissions` for the Object, and store it in the Map called `FieldPermission` in the `PermissionPackage`.
3. If the Permission Set has no permissions to an Object or a Field, there will not be any ObjectPermissions or FieldPermissions records. If ObjectPermissions didn't exist, it'll create a blank `ObjectPermissions` record in the `PermissionPackage`. For each Field, if the `FieldPermissions` didn't exist, it creates one and puts it in the Map.
4. It then goes over all the Permissions flags for each Object at the Object level and for all fields. If the flag is already `true`, it doesn't change it, since the database transaction will fail saying it's a "duplicate". So it tracks a `Dirty` flag for each object and each field, and only updates if something has changed. It is aware if the field is a formula and will apply read permissions but not write. Platform Event only contain permissions to Create and Read at the Object level.

It then groups the `ObjectPermissions` and `FieldPermissions` across all Objects in the batch and upserts them. The upsert is run with partial success allowed -- a practical decision since there are a lot of rules and nuanced things that will cause things to fail. This process does NOT log failed upserts at either the transaction or the field level.

## Other Usage Scenarios

### Running on a Specific Object or Objects
This runs synchronously.
```
UpdatePSAllFieldsAllObjectsQueueable aaq = new UpdatePSAllFieldsAllObjectsQueueable([ID OF YOUR PERMISSION SET IN SINGLE QUOTES]);
aaq.(new List<String>{'Account','My_Object__c'});
```

### Specifying the `RecordsPerQueueable` and the initial `Iteration`
There is a secondary constructor where you can specify these parameters.
```
UpdatePSAllFieldsAllObjectsQueueable aaq = new UpdatePSAllFieldsAllObjectsQueueable([Iteration],[RecordsPerQueueable],[ID OF YOUR PERMISSION SET IN SINGLE QUOTES]);
```

### Limiting The Quantity of Iterations
The process has a variable called `MaxIterations`. Set this to -1 to run on all Objects, 0 to just run the first chunk, or a number greater than 0 if you want to run, say, 5 chunks.

### Available Exclusions
There are quite a few ways to exclude metadata. These can be found in the variables in `initExclusions()`.

## Monitoring and Killing The Process
You can monitor and kill the process in Setup -> Apex Jobs. It might take you a few clicks on the "Abort" button should you need to use it. If the process failed, try to fix the error, then run the process again. For example, if it tells you that certain permission to another object is required before setting it on this one, run that dependent object standalone then run the whole process again.

When it's done, the process will create a Task titled "All Objects / All Fields Process has Completed" and assigned to the running user.

## Other Considerations
* You can try to run this faster by using a larger `RecordsPerQueueable` variable. But some Objects have a _lot_ of fields, and you will swiftly run into the limit of 10k DML records processed per transaction. In testing 10 seems like a safe value that also runs reasonably quickly.
* Because `ModifyAllData` can have a lot of dependencies when turned on in an existing Permission Set, we recommend that you create a new Permission Set, enable ModifyAllData, then run this process on it.
* Throughout this process, we're dealing with metadata that we query from Salesforce. It comes back in all kinds of different formats.  For example, a field may come back with the object name prepended, like Account.Name, in one case and just Name in another.  Since Maps are case sensitive, nearly all object and field names are set to all lower case.
* Warning: inserting Permissions via the Metadata API or DML will allow you to do things that aren't allowed. For example, of you insert Delete permission on a Platform Event, it won't stop you, but you will not be able to edit your Permission Set in the UI. It's strongly recommended to start with a new Permission Set, or a cloned version of your existing one.
* Some permissions have prerequistes. For example, you aren't allowed to set Read on `CommSubscriptionConsent` unless you also have Read permissions on `ContactPointAddress`. You can use the `ProcessFirst` list to force certain objects to be processed at the front of the line.
* You can specify namespaces to exclude, translate Object names, exclude Objects, and exclude Fields by adding values to the Class variables in `initExclusions()`.
* Deliberately no test code provided. Please don't run this in production.
* With `RecordsPerQueueable` set to 20, it processed approximately 1050 Objects in about 15 minutes in a dev sandbox.
* This process is quite fault tolerant so you can run it multiple times on the same PS if necessary.
* Yes, I know this process uses a lot of `debug` statements. The VSCode/SFDX debugger is buggy and I often wasn't able to see inside variables to the depth I needed. So sue me :)

