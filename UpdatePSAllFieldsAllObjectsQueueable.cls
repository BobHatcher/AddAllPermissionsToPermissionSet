/**
 * UpdatePSAllFieldsAllObjectsQueueable
 * Bob Hatcher Sept 2024 @BobHatcher
 * Provided under GNU General Public License 3.0 (GPLv3)
 *      https://www.gnu.org/licenses/gpl-3.0.en.html
 * 
 * >>>>>>> NO WARRANTY EXPRESSED OR IMPLIED <<<<<<<<<
 * >>>>>>> USE AT YOUR OWN RISK <<<<<<<<<
 * 
 * PLEASE REVIEW THE README:
 * https://github.com/BobHatcher/AddAllPermissionsToPermissionSet/edit/master/README.md
 * 
 * 
 */

public with sharing class UpdatePSAllFieldsAllObjectsQueueable implements Queueable {
    // Setting this once since it is heavy and we don't want to be calling it more than once.
    private static Map<String,Schema.Sobjecttype> globalDescribe =Schema.getGlobalDescribe();
    // These are fields that we know we can not apply permissions to.
    private static final Set<String> auditFields = new Set<String>{'currencyisocode','ownerid','recordtypeid','createdbyid','createddate','lastmodifieddate','lastmodifiedbyid','systemmodstamp','isdeleted'};
    private static final Long runId =  Datetime.now().getTime();

    // For testing, set this value to the number of queueables you want to run
    // For example if you set it to 2 it will only run on the first two chunks
    // For all, set to -1; to run once set to 0
    private static Integer MaxIterations = -1;

    public String PermissionSetId {get;set;}
    public Integer RecordsPerQueueable {get;set;}
    public Integer Iteration {get;set;}
    public Map<String,String> FieldNameReplacements {get;set;}
    public Map<String,String> ObjectNameReplacements {get;set;}
    public Set<String> ObjectExclusions {get;set;}
    public Set<String> NamespaceExclusions {get;set;}
    public Set<String> ProcessFirst {get;set;}

    // This is a String that is updated regularly indicating what the system is up to.
    // If there is a failure, the latest message will be published to the debug log
    // alongside the technical error.
    public String Status {get;set;}

    // Simplified constructor. Recommend using this in most cases.
    public UpdatePSAllFieldsAllObjectsQueueable(String permissionSetToBuildId) {
        commonConstructor(0,2,permissionSetToBuildId);
        
    }

    // Configurable constructor, if you want to set the chunk size (i.e., "batch size", or how many objects to process per queueable instance)
    public UpdatePSAllFieldsAllObjectsQueueable(Integer chunkSize, String permissionSetToBuildId) {
        commonConstructor(0,chunkSize,permissionSetToBuildId);
        
    }

    // Do not use this constructor to kick off the process. This is the constructor the process uses to call itself.
    public UpdatePSAllFieldsAllObjectsQueueable(Integer iter, Integer chunkSize, String permissionSetToBuildId) {
        commonConstructor(iter,chunkSize,permissionSetToBuildId);
        
    }

    private void commonConstructor(Integer iter, Integer chunkSize, String permissionSetToBuildId){
        PermissionSetId = permissionSetToBuildId;
        Iteration = iter;
        RecordsPerQueueable = chunkSize;
        
        if (!validateObjectQuantity()){
            return;
        }
        // This object contains known issues/changes that need to be made to field names.
        // For example, on Event, FieldPermissions calls the field locationid but the schema says location
        FieldNameReplacements = new Map<String,String>();
        FieldNameReplacements.put('event.locationid','location');
        // If you need to swap out any any object names, you can add that here.
        ObjectNameReplacements = new Map<String,String>();
        ObjectNameReplacements.put('systemobjectname','replacmentobjectname');
        // These are some objects that seem to exist behind the scenes but permissions do not apply
        // Any object name can be added here.
        ObjectExclusions = new Set<String>{'knowledgearticleversion'};

        NamespaceExclusions = new Set<String>{'agf__'};
    
        // These objects will be processed first. Some objects require access in order to apply permissions
        // to other objects. For example, CommSubscriptionConsent requires read access to ContactPointAddress.
        ProcessFirst = new Set<String>{'ContactPointAddress'};

        if (MaxIterations != -1){
            System.debug('\n\n\n\n*********** \nWARNING: PROCESS IS NOT SET TO RUN OVER ALL OBJECTS \n***********\n\n\n\n\n');
        }
    }

    private Boolean validateObjectQuantity(){
        // This queries the total quantity of objects in the org that will be processed.
        // Since EntityDefinition doesn't support more than 2000 records coming back, abort if we find more than that many.
        Boolean isOK = false;
        try {
            List<sObject> entityDefinitions = Database.query(getBaseEntityDefinitionQuery());
            isOK = entityDefinitions.size() < 2000;
            System.debug('Total ' + entityDefinitions.size() + ' Objects to Process.');
        } catch (Exception e) {
            isOK = false;
        }
        if (!isOK){
            system.debug('Error: you have more than 2000 objects; this process can not be used.');
        }
        return isOK;
    }

    /***********************************
     * EXECUTE
     **********************************/
    public void execute(QueueableContext context) {
        // Main executable.
        // The strategy here is to pull the objects with an OFFSET and a LIMIT.
        // The first time through, Iteration is 0, so offset is 0*5 = 0. If RecordsPerQueueable is 5, this will pull five records
        // starting with the 0th record returned.
        // The next time through, Iteration is 1, so it will pull 5 more records starting with result #5.
        // This is basically mimicing the chunking that the batch process does for us.. if only we could use batch.
        System.debug('Commencing Iteration ' + Iteration + ' with PermissionSetId ' + PermissionSetId);
        
        List<String> objectNames = buildObjectList();
        if (objectNames == null){
            return; // Process is done
        }

        //System.debug('Processing ' + entityDefinitions.size() + ' objects: ' + objectNames);
        try {
            // Invoke the main process on the objects returned by the query.
            go(objectNames);
        } catch (Exception e){
            System.debug('GOT ERROR IN \'go\' METHOD: \nStatus: '+Status+'\n' + e.getMessage());
            throw e;
        }

        // MaxIterations is a failsafe for testing. If you set it to 5, it will only run five instances of the Queueable before stopping.
        if ((MaxIterations == -1 || Iteration < MaxIterations) && MaxIterations != 0){
            // Create a new Queueable to go over the next chunk.
            UpdatePSAllFieldsAllObjectsQueueable aaq = new UpdatePSAllFieldsAllObjectsQueueable(Iteration + 1, RecordsPerQueueable, PermissionSetId);
            System.enqueueJob(aaq); 
        } else {
            System.debug('Hit max iteration value of '+MaxIterations+'. Not enqueing any further instances.');
        }
    }

    /***********************************
     * GO
     **********************************/
    public void go(List<String> objectNames){
        // This is the main process for a given chunk.
        System.debug('Processing ' + objectNames);
        Map<String,Map<String,FieldInfo>> fieldInfo = buildFieldInfo(objectNames);
        if (fieldInfo == null){
            // No more Objects to process
            return;
        }
        Map<String,PermissionPackage> permInfo = getExistingPermissions(objectNames, fieldInfo);
        permInfo = buildObjectPermissions(permInfo);
        permInfo = buildFieldPermissions(permInfo, fieldInfo);
        List<ObjectPermissions> opToUpdate = new List<ObjectPermissions>();
        List<FieldPermissions> fpToUpdate = new List<FieldPermissions>();
        for (PermissionPackage pp : permInfo.values()){
            if (pp.IsObjectPermissionDirty){
                Status = 'Populating list of ObjectPermissions in preparation for the upsert.';
                opToUpdate.add(pp.ObjectPermission);
            }
            for (String fieldName : pp.FieldPermission.keySet()){
                if (!pp.IsPlatformEvent && pp.IsFieldPermissionDirty.get(fieldName.toLowercase()))
                    Status = 'Populating list of ObjectPermissions in preparation for the upsert.';
                    fpToUpdate.add(pp.FieldPermission.get(fieldName.toLowercase()));
            }
                
        }
        
        try {
            System.debug('Upserting ' + opToUpdate.size() + ' ObjectPermissions Records');
            List<Database.UpsertResult> results = Database.upsert(opToUpdate, false);
            
        } catch (Exception e){
            system.debug(e.getMessage());
            throw new DMLException('Unable to Perform DML Operation on ObjectPermissions : ' +e.getMessage());
        }
        try {
            System.debug('Upserting ' + fpToUpdate.size() + ' FieldPermissions Records');
            List<Database.UpsertResult> results = Database.upsert(fpToUpdate, false);
            
        } catch (Exception e){
            system.debug(e.getMessage());
            throw new DMLException('Unable to Perform DML Operation on FieldPermissions : ' +e.getMessage());
        }
        
        
    }

    /***********************************
     * BUILD OBJECT LIST
     **********************************/
    public List<String> buildObjectList(){
        List<String> objectNames = new List<String>();
        objectNames.addAll(ProcessFirst);
        Integer offset = Iteration * RecordsPerQueueable;

        
        String query = getBaseEntityDefinitionQuery() + '  LIMIT :RecordsPerQueueable OFFSET : offset';
        List<EntityDefinition> entityDefinitions = (List<EntityDefinition>) Database.query(query);
        
        // If the query doesn't return anything, the process dies.
        if (entityDefinitions.size() == 0){
            System.debug('No more objects to process. Exiting.');
            insert new Task(OwnerId = UserInfo.getUserId(), Subject = 'All Objects / All Fields Process has Completed');
            return null;
        }
        // Simplify to a list of object names.
        for (EntityDefinition ed : entityDefinitions){
            // We want to include objects where customizable is TRUE, OR they are a platform event.
            // EntityDefinition queries don't support OR clauses ('Disjunctions not supported')
            Boolean isNamespaceExcluded = false;
            for (String ns : NamespaceExclusions){
                if (ed.QualifiedAPIName.startsWith(ns)){
                    isNamespaceExcluded = true;
                }
            }

            // If it is on the ProcessFirst list, it was added when the list was created at the top of this method.
            if (!ProcessFirst.contains(ed.QualifiedApiName.toLowerCase()) && !isNamespaceExcluded && !ObjectExclusions.contains(ed.QualifiedApiName.toLowerCase()) && (ed.IsCustomizable || ed.QualifiedAPIName.endsWith('__e'))){
                if (ObjectNameReplacements.containsKey(ed.QualifiedApiName.toLowerCase())){
                    objectNames.add(ObjectNameReplacements.get(ed.QualifiedApiName.toLowerCase()));
                } else {
                    objectNames.add(ed.QualifiedApiName.toLowerCase());
                }
            } 
        }
        System.debug('After paring down, will process ' + objectNames.size() + ' Objects.');
        return objectNames;
    }

    /***********************************
     * GET BASE ENTITY DEFINITION QUERY
     **********************************/
    public String getBaseEntityDefinitionQuery(){
        // This is common to two queries in this process.
        // the main go() process appends the OFFSET and LIMIT, so using the Database.query method rather than [] notation.
        return 'SELECT QualifiedApiName, IsCustomizable FROM EntityDefinition WHERE (NOT(QualifiedAPIName LIKE \'%__mdt\')) AND (NOT(QualifiedAPIName LIKE \'%__Tag\')) AND (NOT(QualifiedAPIName LIKE \'%__Share\')) AND (NOT(QualifiedAPIName LIKE \'%__ChangeEvent\')) AND (NOT(QualifiedAPIName LIKE \'%__History\')) AND (NOT(QualifiedAPIName LIKE \'%__Feed\')) AND (NOT(QualifiedAPIName LIKE \'%__VoteStat\')) AND (NOT(QualifiedAPIName LIKE \'%__ViewStat\')) AND (NOT(QualifiedAPIName LIKE \'%__DataCategorySelection\')) order by QualifiedApiName ';
        
    }

    /* ##################################################################################################################################
    *                                                      DATA SETUP METHODS
    ################################################################################################################################## */
    /***********************************
     * BUILD FIELD INFO
     **********************************/
    public Map<String,Map<String,FieldInfo>> buildFieldInfo(List<String> objectNames){
        // Build a structure to determine if a field's permissions are modifiable using this process. This will avoid trying to update
        // FieldPermissions on audit fields like SysModStamp.
        // Store in a Map of Maps. The first key is the object name, the second key is the field name.
        Map<String,Map<String,FieldInfo>> fieldInfo = new Map<string,Map<String,FieldInfo>>();
        for (String objectName : objectNames){
            // Instantiate the Map for Field Names in the outer Map by object
            fieldInfo.put(objectName.toLowerCase(), new Map<String,FieldInfo>());

            // Create a Map for the fields in the object.
            // field key is its name only (no object name prepended) and all lower case.
            Map<String,FieldInfo> thisFieldInfo = new Map<String,FieldInfo>();

            // Iterate over all fields in the object from the schema.
            // In the inner Map, add a true/false flag.
            Status = 'buildFieldInfo / ' + objectName + ' - calling globalDescribe';
            Map<String, Schema.SObjectField> fields = globalDescribe.get(objectName.toLowerCase()).getDescribe().fields.getMap();
            for (String fieldName : fields.keySet()){
                //Boolean isUpdateable = fields.get(fieldName.toLowerCase()).getDescribe().isUpdateable();
                //Schema.DescribeFieldResult res = fields.get(fieldName.toLowerCase()).getDescribe();
                Status = 'buildFieldInfo / ' + objectName + ' - building FieldInfo for field : ' + fieldName;
                FieldInfo fi = new FieldInfo(
                    fieldName,
                    fields.get(fieldName.toLowerCase()).getDescribe().isUpdateable(),
                    fields.get(fieldName.toLowerCase()).getDescribe().isCalculated(),
                    auditFields.contains(fieldName.toLowerCase())
                );
                thisFieldInfo.put(fieldName.toLowerCase(),fi);
            }
            fieldInfo.put(objectName.toLowerCase(), thisFieldInfo);
        }
        return fieldInfo;
    }
        
    /***********************************
     * GET EXISTING PERMISSIONS
     **********************************/
    private Map<String,PermissionPackage> getExistingPermissions(List<String> objectNames, Map<String,Map<String,FieldInfo>> fieldInfo) {
        // This process builds a PermissionPackage that includes the ObjectPermissions and FieldPermissions.
        // There will be one PermissionPackage per object.
        // It is stored in a Map called PermInfo with the object name as a key.
        // This method ensures that a PermissionPackage exists for all objects listed the passed-in list of
        // object names, and that within the package there is a Map containing the field name as key,
        // and a FieldPermissions object as the value.
        // If permissions exist, it will add the existing permissions to the object;
        // if not, it will add a blank ObjectPermissions or FieldPermissions object to be updated in the next method.

        Map<String,PermissionPackage> permInfo = new Map<String,PermissionPackage>();

        // Query existing Object Permissions and populate the PermissionPackage with it if one is found.
        permInfo = addExistingObjectPermissions(permInfo,objectNames);

        // Query existing Field Permissions and populate the PermissionPackage with it if any are found.
        permInfo = addExistingFieldPermissions(permInfo,objectNames, fieldInfo);

        // Fill in objects and fields that did not exist in the query.
        permInfo = addNewObjectsAndFields(permInfo, objectNames, fieldInfo);

        return permInfo;
    }

    /***********************************
     * ADD EXISTING *OBJECT* PERMISSIONS
     **********************************/
    private Map<String,PermissionPackage> addExistingObjectPermissions(Map<String,PermissionPackage> permInfo, List<String> objectNames){
        // Query for existing ObjectPermissions for the in-scope objects and this Permission Set.
        for (ObjectPermissions op : [SELECT Id,sobjecttype, ParentId,  PermissionsCreate, PermissionsDelete, PermissionsEdit, PermissionsRead, PermissionsViewAllRecords, PermissionsModifyAllRecords FROM ObjectPermissions WHERE ParentId = :PermissionSetId and sobjectType in : objectNames ])
        {
            Status = 'Adding existing object permissions for ' + op.sObjectType ;
            // Create the PermissionPackage if necessary. The constructor sets the ParentId of the ObjectPermissions to the PermissionSetId.
            if (permInfo.get(op.sObjectType.toLowerCase()) == null){
                permInfo.put(op.sObjectType.toLowerCase(), new PermissionPackage(op.sObjectType, permissionSetId));
            }

            // Pull the ObjectPermissions from the PermissionPackage, 
            // assign the ObjectPermissions we just queried, and put it back in the permInfo object.
            PermissionPackage pp = permInfo.get(op.sObjectType.toLowerCase());
            pp.ObjectPermission = op;
            permInfo.put(op.sObjectType.toLowerCase(), pp);
        }
        return permInfo;
    }

    /***********************************
     * ADD EXISTING *FIELD* PERMISSIONS
     **********************************/
    private Map<String,PermissionPackage> addExistingFieldPermissions(Map<String,PermissionPackage> permInfo, List<String> objectNames, Map<String,Map<String,FieldInfo>> fieldInfo){
        for (FieldPermissions perm : [SELECT Id, Field, ParentId, PermissionsRead, PermissionsEdit, sObjectType FROM FieldPermissions WHERE sObjectType IN : objectNames and ParentId = :PermissionSetId ORDER BY sObjectType])
        {
            // This queries the FieldPermissions for this Permission Set for in-scope objects
            // and builds out the FieldPermission Map in the PermissionPackage.

            // perm.Field comes back as Object.Field i.e. Account.Name
            // Parameter to split() is a regex so we need to double escape it
            String  fieldNameOnly = perm.Field.split('\\.')[1].toLowerCase();
            // perm.Field comes back as Object.Field i.e. Account.Name
            String replacementKey = (perm.Field).toLowerCase();
            if (FieldNameReplacements.containsKey(replacementKey)){
                Status = 'Replacing Field Name : ' + replacementKey;
                fieldNameOnly = FieldNameReplacements.get(replacementKey);
                System.debug('Replaced field name for ' + perm.Field + ' to ' + FieldNameReplacements.get(replacementKey));
            } 

            // If it's not possible to even read the field, we don't want to add it to the FieldPermission Map in the PermissionPackage.
            if (fieldInfo?.get((perm?.sObjectType.toLowerCase()))?.get(fieldNameOnly?.toLowerCase())?.SetRead){
                // Just to be safe, if we don't have a PermissionPackage for this object yet, create it.
                if (permInfo.get(perm.sObjectType.toLowerCase()) == null){
                    PermissionPackage pp = new PermissionPackage(perm.sObjectType.toLowerCase(), permissionSetId);
                    // If we're here, we missed setting up the object permissions above.
                    pp = buildSingleObjectPermissions(pp);
                    permInfo.put(perm.sObjectType.toLowerCase(), pp);
                }
                PermissionPackage pp = permInfo.get(perm.sObjectType.toLowerCase());
                
                // If the PermissionPackage's list of FieldPermissions doesn't have an entry for this field yet,
                // Create one.
                if (pp.FieldPermission.get(fieldNameOnly.toLowerCase()) == null){
                    pp.fieldPermission.put(fieldNameOnly.toLowerCase(), new FieldPermissions());
                }
                // Add the FieldPermissions from the query to the Map in the PermissionPackage.
                Status = 'Adding existing FieldPermissions to the permInfo object.';
                pp.FieldPermission.put(fieldNameOnly.toLowerCase(), perm);
                permInfo.put(perm.sObjectType.toLowerCase(), pp);
            } 
        }
        return permInfo;
    }

    /***********************************
     * ADD NEW OBJECTS AND FIELDS
     **********************************/
    private Map<String,PermissionPackage> addNewObjectsAndFields(Map<String,PermissionPackage> permInfo, List<String> objectNames,  Map<String,Map<String,FieldInfo>> fieldInfo){
        // If a user doesn't have permission at all to a given object or field, there won't be any records in ObjectPermissions
        // or FieldPermissions. We want to make sure that a PermissionPackage exists for all the objects we're processing,
        // and all updateable fields are present in the FieldPermission map in the PermissionPackage.

        for (String objectName : objectNames){
            // lc = lower case
            String lcObjectName = objectName.toLowerCase();
            // Create the PermissionPackage if necessary. The constructor sets the ParentId of the ObjectPermissions to the PermissionSetId.
            if (permInfo.get(objectName.toLowerCase()) == null){
                PermissionPackage pp = new PermissionPackage(objectName.toLowerCase(), permissionSetId);
                // If we're here, we missed setting up the object permissions above.
                pp = buildSingleObjectPermissions(pp);
                permInfo.put(objectName.toLowerCase(), pp);
            }
            
            if (!permInfo.get(objectName.toLowerCase()).IsPlatformEvent){
                Map<String, Schema.SObjectField> fields = globalDescribe.get(objectName.toLowerCase()).getDescribe().fields.getMap();
                for(String fieldName : fields.keyset() ){
                    // Field name comes back from the schema as the field name only (no object name prepended) and all lower case.
                    // Use the fieldInfo package 
                    // Since we processed object level first, we can assume there is a PermissionPackage for this object.
                    PermissionPackage pp = permInfo.get(objectName.toLowerCase());
                    Status = 'Creating a blank FieldPermissions for ' + objectName + ' / ' + fieldName;
                    if (!pp.FieldPermission.containsKey(fieldName.toLowerCase())){
                        pp.FieldPermission.put(fieldName.toLowerCase(),new FieldPermissions(
                            Field = objectName.toLowercase() + '.' + fieldName.toLowerCase(),
                            sObjectType=lcObjectName,
                            ParentId=permissionSetId));
                    }
                    permInfo.put(pp.ObjectName.toLowerCase(), pp);
                    
                }
            }
            
        }

        return permInfo;
    }

    /* ##################################################################################################################################
    *                                                      METHODS TO ADD PERMISSIONS
    ################################################################################################################################## */

    /***********************************
     * BUILD (ALL) OBJECT PERMISSIONS
     **********************************/
    // This takes care of the ObjectPermissions for the objects in the package.
    private Map<String,PermissionPackage> buildObjectPermissions(Map<String,PermissionPackage> permInfo){
        Map<String,PermissionPackage> out = new Map<String,PermissionPackage>();
        // Iterate over each package, and send each to buildSingleObjectPermissions() to populate.
        for (PermissionPackage pPkg : permInfo.values()){
            PermissionPackage ppWithObjectPermissions = buildSingleObjectPermissions(pPkg);
            out.put(pPkg.ObjectName.toLowerCase(),ppWithObjectPermissions);
        }
        return out;
    }

    /***********************************
     * BUILD SINGLE OBJECT PERMISSIONS
     **********************************/
    private PermissionPackage buildSingleObjectPermissions(PermissionPackage pp){
        // This goes over each permission in Object Permissions.
        // We don't want to update it if we don't have to, so it doesn't update the flag if it is already set.
        // isDirty indicates whether the object was updated. If it is NOT dirty, we will exclude it from the
        // eventual upsert.
        Status = 'Building Object Permissions for ' + pp.ObjectName;
        if (pp.ObjectPermission.sObjectType == null){
            pp.ObjectPermission.sObjectType = pp.ObjectName;
        }
        if (pp.ObjectPermission?.PermissionsRead == null || !pp.ObjectPermission.PermissionsRead){
            pp.ObjectPermission.PermissionsRead = true;
            pp.IsObjectPermissionDirty = true;
        }
        if (pp.ObjectPermission.PermissionsCreate == null || !pp.ObjectPermission.PermissionsCreate) {
            pp.ObjectPermission.PermissionsCreate = true;
            pp.IsObjectPermissionDirty = true;
        }
        if (!pp.IsPlatformEvent){
            // The following permissions are not applicable to platform events.
            if (pp.ObjectPermission.PermissionsViewAllRecords == null || !pp.ObjectPermission.PermissionsViewAllRecords)
            {
                pp.ObjectPermission.PermissionsViewAllRecords = true;
                pp.IsObjectPermissionDirty = true;
            }
            if (pp.ObjectPermission.PermissionsDelete == null || !pp.ObjectPermission.PermissionsDelete) {
                pp.ObjectPermission.PermissionsDelete = true;
                pp.IsObjectPermissionDirty = true;
            }
            
            if (pp.ObjectPermission.PermissionsEdit == null || !pp.ObjectPermission.PermissionsEdit) {
                pp.ObjectPermission.PermissionsEdit = true;
                pp.IsObjectPermissionDirty = true;
            }
            if (pp.ObjectPermission.PermissionsModifyAllRecords == null || !pp.ObjectPermission.PermissionsModifyAllRecords) {
                pp.ObjectPermission.PermissionsModifyAllRecords = true;
                pp.IsObjectPermissionDirty = true;
            }
        }
        
        return pp;
    }

    /***********************************
     * BUILD *ALL* FIELD PERMISSIONS
     **********************************/
    private Map<String,PermissionPackage> buildFieldPermissions(Map<String,PermissionPackage> permInfo, Map<String,Map<String,FieldInfo>> fieldInfo){
        
        // This takes care of the FieldPermissions for the objects in the package.

        Map<String,PermissionPackage> out = new Map<String,PermissionPackage>();
        // Iterate over each PermissionPackage and drill into the FieldPermissions within.
        for (PermissionPackage pp : permInfo.values()){
            PermissionPackage tempPP = pp;
            // Field permissions do not apply to platform events
            if (!pp.IsPlatformEvent){
                for (String fieldName : pp.FieldPermission.keySet()){
                    // Call buildSingleFieldPermissions to build out the single field permissions.
                    // Note that since this is a List, we can't set a simple flag in the PermissionPackage
                    // like we did with objects. So a small helper class will help track whether each FieldPermissions is dirty.
                    FieldPermissionInfo fp = buildSingleFieldPermissions(pp.FieldPermission.get(fieldName.toLowerCase()), fieldInfo.get(pp.ObjectName.toLowerCase()).get(fieldName.toLowerCase()));
                    
                    tempPP.IsFieldPermissionDirty.put(fieldName.toLowerCase(),fp.IsDirty);
                    tempPP.FieldPermission.put(fieldName.toLowerCase(),fp.FieldPermission);
                } 
                out.put(pp.ObjectName.toLowerCase(),tempPP);
            } else {
                out.put(pp.ObjectName.toLowerCase(),pp);
            }
        }
        
        return out;
    }

    /***********************************
     * BUILD *SINGLE* FIELD PERMISSIONS
     **********************************/
    public FieldPermissionInfo buildSingleFieldPermissions(FieldPermissions fp, FieldInfo fieldInfo){
        // Set each permission on the FieldPermissions and track whether it's dirty
       
            //system.debug('*****' + fieldInfo);
        
        Boolean isDirty=false;
        Status = 'Setting field permissions for ' + fp.Field + ' / SetRead: ' + fieldInfo.SetRead + ' / Existing PermissionsRead: ' + fp.PermissionsRead;
        if ((fieldInfo.SetRead) && (fp.PermissionsRead == null || fp.PermissionsRead == false)){
            fp.PermissionsRead = true;
            isDirty=true;
        }
        // Don't attempt to write Edit permissions to formulas.
        Status = 'Setting field permissions for ' + fp.Field + ' / SetRead: ' + fieldInfo.SetUpdate + ' / Existing PermissionsEdit: ' + fp.PermissionsEdit;
        if (fieldInfo.SetUpdate && (fp.PermissionsEdit == null || fp.PermissionsEdit == false)){
            fp.PermissionsEdit = true;
            isDirty=true;
        }
        
        
        return new FieldPermissionInfo(fp,isDirty);
    }

    /* ##################################################################################################################################
    *                                                     INTERNAL DATA STRUCTURES
    ################################################################################################################################## */
    /***********************************
    *   FIELDPERMISSIONINFO
     **********************************/
    public Class FieldPermissionInfo{
        // Simple helper class to return the FieldPermissions object as well as the dirty flag.
        public Boolean IsDirty {get;set;}
        public FieldPermissions FieldPermission {get;set;}
        public FieldPermissionInfo(FieldPermissions fp, Boolean dirtyFlag){
            IsDirty=dirtyFlag;
            FieldPermission = fp;
        }
    }
    
    /***********************************
    *   PERMISSIONPACKAGE
     **********************************/
    private Class PermissionPackage{
        // This is the core internal class that maintains all permissions for a given object.
        // There is ONE ObjectPermissions object per object.
        public ObjectPermissions ObjectPermission {get;set;}
        // Since there are multiple fields, we have to maintain a data structure.
        // This maintains a map of the FIELD name to a FieldPermissions object
        public Map<String,FieldPermissions> FieldPermission {get;set;}
        public String ObjectName {get;set;}
        // Tracks whether the object permission was updated
        public Boolean IsObjectPermissionDirty {get;set;}
        // Tracks whether the permissions for each field was updated
        public Map<String,Boolean> IsFieldPermissionDirty {get;set;}
        public Boolean IsPlatformEvent {get;set;}

        public PermissionPackage(String objName, String permissionSetId){
            // By convention we're keeping everything in lower case.
            ObjectName = objName.toLowerCase();
            // Basic instantiations
            FieldPermission = new Map<String,FieldPermissions>();
            ObjectPermission = new ObjectPermissions();
            ObjectPermission.ParentId = permissionSetId;
            IsFieldPermissionDirty = new Map<String,Boolean>();
            IsObjectPermissionDirty = false;
            IsPlatformEvent = objName.endsWithIgnoreCase('__e');
        }
        public override String toString(){
            JSONGenerator generator = JSON.createGenerator(true);
            generator.writeObject(ObjectPermission);
            String out = generator.getAsString();
            for (FieldPermissions fp: FieldPermission.values()){
                generator.writeObject(fp);
                out += generator.getAsString();
            }
            return out;
        }
    }

    /***********************************
    *   FIELDINFO
     **********************************/
    public Class FieldInfo{
        public String Name {get;set;}
        public Boolean IsFormula {get;set;}
        public Boolean IsUpdateable {get;set;}
        public Boolean IsAuditField {get;set;}
        public Boolean SetRead { get {
            // No scenarios found where we would not want to apply read permission.
            return true;
        }}
        public Boolean SetUpdate { get{
            return !IsAuditField && IsUpdateable && !IsFormula;
        }}
        public FieldInfo(String fName, Boolean isUpdate, Boolean isForm, Boolean isAudit){
            Name = fName.toLowerCase();
            IsFormula = isForm;
            IsUpdateable = isUpdate;
            IsAuditField = isAudit;
        }

        
    }
    
}
