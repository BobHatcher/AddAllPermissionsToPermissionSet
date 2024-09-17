/**
 * UpdatePSAllFieldsAllObjectsQueueable
 * Bob Hatcher Sept 2024 @BobHatcher
 * Provided under GNU General Public License 3.0 (GPLv3)
 *      https://www.gnu.org/licenses/gpl-3.0.en.html
 * 
 * >>>>>>> NO WARRANTY EXPRESSED OR IMPLIED <<<<<<<<<
 * >>>>>>> USE AT YOUR OWN RISK <<<<<<<<<
 * 
 *  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 *  ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
 *  OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL
 *  THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 *  EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 *  OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
 *  OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 *  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 * 
 * PLEASE REVIEW THE README:
 * https://github.com/BobHatcher/AddAllPermissionsToPermissionSet/edit/master/README.md
 * 
 * 
 */

public with sharing class UpdatePSAllFieldsAllObjectsQueueable implements Queueable,  Database.AllowsCallouts {
    // Setting this once since it is heavy and we don't want to be calling it more than once.
    private static Map<String,Schema.Sobjecttype> globalDescribe =Schema.getGlobalDescribe();
    // These are fields that we know we can not apply permissions to.
    private static final Set<String> auditFields = new Set<String>{'currencyisocode','ownerid','recordtypeid','createdbyid','createddate','lastmodifieddate','lastmodifiedbyid','systemmodstamp','isdeleted'};
    
    // For testing, set this value to the number of queueables you want to run
    // For example if you set it to 2 it will only run on the first two chunks
    // For all, set to -1; to run once set to 0
    // Applies to the DML Process only
    private static final Integer MaxIterations = -1;
    public static final Boolean EnableDebug =true;
    public static final Boolean EnableVerboseDebug=true;

    public String PermissionSetId {get;set;}
    public Integer RecordsPerQueueable {get;set;}
    public Integer Iteration {get;set;}
    public Boolean EnableWrite {get;set;}
    public Decimal TotalObjects {get;set;}
    public Decimal TotalObjectsThisIteration {get;set;}
    public String Instruction {get;set;}
    public PermissionSet_x PermSet {get;set;}
    private Set<String> GlobalObjectExclusions {get;set;}
    private Set<String> GlobalNamespaceExclusions {get; set;}
    private Set<String> ApexClassExclusions {get;set;}
    private Set<String> ApexClassNamespaceExclusions {get;set;}
    private Set<String> ApexPageExclusions {get;set;}
    private Set<String> ApexPageNamespaceExclusions {get;set;}
    private Set<String> CustomAppExclusions {get;set;}
    private Set<String> CustomAppNamespaceExclusions {get;set;}
    private Set<String> RecordTypeExclusions {get;set;}
    private Set<String> RecordTypeNamespaceExclusions {get;set;}
    private Set<String> RecordTypeObjectExclusions {get;set;}
    private Set<String> ProcessFirst {get;set;}
    private Map<String,String> ObjectNameReplacements;
    private Map<String,String> FieldNameReplacements;
    // This is a String that is updated regularly indicating what the system is up to.
    // If there is a failure, the latest message will be published to the debug log
    // alongside the technical error.
    public String Status {get;set;}
    
    public static final String INSTRUCTION_TABSOBJECTSANDFIELDS = 'objectsandfields';
    public static final String INSTRUCTION_ADD_APEX_CLASSES = 'addApexClasses';
    public static final String INSTRUCTION_ADD_APEX_PAGES = 'addApexPages';
    public static final String INSTRUCTION_ADD_CUSTOM_APPS = 'addCustomApps';
    public static final String INSTRUCTION_ADD_RECORDTYPES = 'addRecordTypes';
    public static final String INSTRUCTION_UPDATE_METADATA = 'updateMetadata';
    public static final String INSTRUCTION_START = 'start';

    // Simple constructor to kick off the process with default values.
    public UpdatePSAllFieldsAllObjectsQueueable(String permissionSetToBuildId) {
        this(INSTRUCTION_START,0,20,permissionSetToBuildId,true, new PermissionSet_x());
    }

    // Simple constructor to kick off the process and set the write flag.
    public UpdatePSAllFieldsAllObjectsQueueable(String permissionSetToBuildId, Boolean enableWrite) {
        this(INSTRUCTION_START,0,20,permissionSetToBuildId,enableWrite, new PermissionSet_x());
    }

    // Configurable constructor, if you want to set the chunk size (i.e., "batch size", or how many objects to process per queueable instance)
    public UpdatePSAllFieldsAllObjectsQueueable(Integer chunkSize, String permissionSetToBuildId, Boolean ew) {
        this(INSTRUCTION_START,0,chunkSize,permissionSetToBuildId,ew,null);
    }

    // Do not use this constructor to kick off the process. This is the constructor the process uses to call itself.
    public UpdatePSAllFieldsAllObjectsQueueable(String instr, Integer iter, Integer chunkSize, String permissionSetToBuildId, Boolean ew, PermissionSet_x ps) {
        initExclusions();
        Instruction = instr;
        PermSet = (ps == null ? new PermissionSet_x() : ps);
        PermissionSetId = permissionSetToBuildId;
        Iteration = iter;
        RecordsPerQueueable = chunkSize;
        EnableWrite = ew;
        
        if (MaxIterations != -1){
            system.debug('\n\n\n\n*********** \nWARNING: PROCESS IS NOT SET TO RUN OVER ALL OBJECTS \n***********\n\n\n\n\n');
        }
    }

    private void initExclusions(){
        
        ///// GLOBAL EXCLUSIONS

        // Global object exclusions - applies to all parts.
        // If you need to replace an object name wholesale
        GlobalObjectExclusions= new Set<String>{'knowledgearticleversion'};
        GlobalNamespaceExclusions = new Set<String>{'agf','loop','et4ae5','field_trip','APXT_BPM'.toLowerCase()};
       

        ///// METADATA API EXCLUSIONS & MAPPINGS (ApexClass, ApexPage, CustomApp, Record Type)
        ApexClassExclusions = new Set<String>{'EmailTrackingService','EmailTrackingServiceTest','MissingParamsException','MissingParamsExceptionTest','OutlookComposeController',
        'OutlookComposeControllerTest','OutlookAuthController','OutlookAuthControllerTest','PardotEndpointHelper','PardotEndpointHelperTest','TrackedEmailEndpoint',
        'TrackedEmailEndpointTest','AsyncRequest','AsyncRequestTest','AsyncRequestBatch','AsyncRequestBatchTest','AsyncRequestBatchProcessor','AsyncRequestBatchProcessorTest',
        'AsyncRequestOCLPruningBatch','AsyncRequestOCLPruningBatchTest','AsyncRequestOCLPruningBatch','AsyncRequestOCLPruningBatchTest','OutlookEmail','OutlookEmailTest'};
        // To exclude all Apex Classes that have a Namespace, enter '*' as a value in the List.
        ApexClassNamespaceExclusions = new Set<String>();

        ApexPageExclusions = new Set<String>{'ComposerSolution'};
        // To exclude all Apex Pages that have a Namespace, enter '*' as a value in the List.
        ApexPageNamespaceExclusions = new Set<String>{'pi','APXTConga4','activities','permissioner','MassManager','*'};

        // CustomAppExclusions: Use DeveloperName as shown in the AppDefinition table
        CustomAppExclusions = new Set<String>{'ExpressionSetConsole','SalesCloudMobile'};
        // To exclude all Custom Apps that have a Namespace, enter '*' as a value in the List.
        CustomAppNamespaceExclusions = new Set<String>();

        RecordTypeExclusions = new Set<String>{'Campaign.Innovation_Hub_Event'.toLowerCase()};
        // Excludes from Record Type processing only -- useful if licenses aren't fully applied to your account
        // To exclude all RT's that have a Namespace, enter '*' as a value in the List.
        RecordTypeNamespaceExclusions = new Set<String>{'agf','loop','et4ae5','innohub','copado','cloudx_cms','APXT_CMQM'.toLowerCase()};
        // Exclude Record Types related to these objects.
        RecordTypeObjectExclusions = new Set<String>{'LSC1__Requisition_Item__c','LSC1__Requisition__c','innohub__Activity__c'};
    
        ///// DML PROCESS EXCLUSIONS & MAPPINGS (Objects & Fields)

        // Object & Field process will process these objects at the start. 
        ProcessFirst = new Set<String>{'ContactPointAddress'};
        // These are some objects that seem to exist behind the scenes but permissions do not apply
        // Any object name can be added here.
        ObjectNameReplacements = new Map<String,String>{'systemobjectname'=>'replacmentobjectname'};
        // This object contains known issues/changes that need to be made to field names.
        // For example, on Event, FieldPermissions calls the field locationid but the schema says location
        FieldNameReplacements = new Map<String,String>{'event.locationid'=>'location','case.source'=>'sourceid','livechattranscript.locationid'=>'location','location.locationid'=>'location'};
    }

    /***********************************
     * EXECUTE
     **********************************/
    public void execute(QueueableContext context) {
        // Main executable.
        PermissionSet_x ps = PermSet;
        String next = '';
        Status = '\n\n ***** Starting Execute with Instruction ' + Instruction + ' Iteration=' + Iteration;
        debug(status);
        if (Instruction == INSTRUCTION_START){
            // Step 1: Query the existing PermissionSet via Metadata API.
            try {
                ps = getExistingPermissionSetViaMdAPI(PermissionSetId);
            } catch (UpdatePSException e){
                debug('\n\nLatest Status='+Status+'\nError In Instruction '+Instruction+':\n '+e.getMessage());
                throw e;
            }
            // if the Permissionset was null, a new queueable was spawned to retry
            if (ps == null)
                return;
            next = INSTRUCTION_ADD_APEX_CLASSES;
        } else if (Instruction == INSTRUCTION_ADD_APEX_CLASSES){
            // Step 2: Add Apex Class permissions to the PermissionSet.
            try {
                ps = addApexClassPermissions(ps);
            } catch (UpdatePSException e){
                debug('\n\nLatest Status='+Status+'\nError In Instruction '+Instruction+':\n '+e.getMessage());
                throw e;
            }
            next = INSTRUCTION_ADD_APEX_PAGES;
        } else if (Instruction == INSTRUCTION_ADD_APEX_PAGES){
            // Step 3: Add Apex Page permissios to the PermissionSet.
            try {
                ps = addApexPagePermissions(ps);
            } catch (UpdatePSException e){
                debug('\n\nLatest Status='+Status+'\nError In Instruction '+Instruction+':\n '+e.getMessage());
                throw e;
            }
            next = INSTRUCTION_ADD_CUSTOM_APPS;
        } else if (Instruction == INSTRUCTION_ADD_CUSTOM_APPS){
            // Step 4: Add Custom App permissions to the Permission Set.
            try {
                ps = addCustomAppPermissions(ps);
            } catch (UpdatePSException e){
                debug('\n\nLatest Status='+Status+'\nError In Instruction '+Instruction+':\n '+e.getMessage());
                throw e;
            }
            next = INSTRUCTION_ADD_RECORDTYPES;
        } else if (Instruction == INSTRUCTION_ADD_RECORDTYPES){
            // Step 5: Add Record Types to the Permission set.
            try {
                ps = addRecordTypePermissions(ps);
            } catch (UpdatePSException e){
                debug('\n\nLatest Status='+Status+'\nError In Instruction '+Instruction+':\n '+e.getMessage());
                throw e;
            }
            next = INSTRUCTION_UPDATE_METADATA;
        } else if (Instruction == INSTRUCTION_UPDATE_METADATA){
            // Step 6: Update the Permission Set via Metadata API to add the 
            // permissions added in steps 2-5.
            try {
                pushUpdatedPermissionSetviaMdApi(ps);
            } catch (UpdatePSException e){
                debug('\n\nError In Instruction '+Instruction+':\n '+e.getMessage());
                throw e;
            }
            next = INSTRUCTION_TABSOBJECTSANDFIELDS;
        } else if (Instruction == INSTRUCTION_TABSOBJECTSANDFIELDS){

            // Step 7: Add Object, Field and Tab Permissions via ordinary Apex/DML

            // The strategy here is to pull the objects with an OFFSET and a LIMIT.
            // The first time through, Iteration is 0, so offset is 0*5 = 0. If RecordsPerQueueable is 5, this will pull five records
            // starting with the 0th record returned.
            // The next time through, Iteration is 1, so it will pull 5 more records starting with result #5.
            // This is basically mimicing the chunking that the batch process does for us.. if only we could use batch.
            
            Status = '\n\n ***** Commencing Iteration ' + Iteration + '' + ' with PermissionSetId ' + PermissionSetId + '. RecordsPerQueueable=' + RecordsPerQueueable;
            debug(Status);
            
            List<String> objectNames = buildObjectList();
            if (objectNames == null){
                return; // Process is done
            } else {
                TotalObjectsThisIteration = objectNames?.size();
            }

            Status = 'After filtering out-of-scope objects, now processing objects: ' + objectNames;
            debug(Status);
            try {
                // Invoke the main process on the objects returned by the query for Object/Field permissions.
                dmlProcess(objectNames);
            } catch (Exception e){
                System.debug('GOT ERROR IN \'go\' METHOD: \nStatus: '+Status+'\n' + e.getMessage());
                throw e;
            }

            // MaxIterations is a failsafe for testing. If you set it to 5, it will only run five instances of the Queueable before stopping.
            if ((MaxIterations == -1 || Iteration < MaxIterations) && MaxIterations != 0){
                // Create a new Queueable to go over the next chunk.
                next = INSTRUCTION_TABSOBJECTSANDFIELDS;

            } else {
                next = 'Stop'; 
                System.debug('Hit max iteration value of '+MaxIterations+'. Not enqueing any further instances.');
            } 
            
        }

        if (next != 'Stop'){
            // The first time we call this for Objects+Fields we don't want to increment the Iteration
            
            Integer thisIteration = 0;
            // If this is after the metadata update and we are moving on to the DML (tabs/objects/fields)
            // for the first time, Iteration has to be 0 and we can't autoincrement it.
            if (Instruction == INSTRUCTION_UPDATE_METADATA && next == INSTRUCTION_TABSOBJECTSANDFIELDS){
                thisIteration = 0;
            } else if (Instruction == INSTRUCTION_TABSOBJECTSANDFIELDS) {
                thisIteration = ++ Iteration ;
            } else {
                thisIteration = 0;
            }
            Status = 'Enqueueing next Metadata API Step: ' + next + ', Finishing Iteration ' + Iteration + ' and calling next with thisIteration='+thisIteration;
            debug(Status);
            UpdatePSAllFieldsAllObjectsQueueable aaq = new UpdatePSAllFieldsAllObjectsQueueable(next, thisIteration, RecordsPerQueueable, PermissionSetId, EnableWrite, ps);
            System.enqueueJob(aaq); 
        }
        
        
        
    }

    /* ##################################################################################################################################
    *                                                    PART 1: PERMISSIONS TO ADD VIA METADATA API
    ################################################################################################################################## */
    
    /***********************************
    *   GETEXISTINGPERMISSIONSETVIAMDAPI
     **********************************/
    public PermissionSet_x getExistingPermissionSetViaMdAPI(Id psId){
        // Retrieves the current PermissionSet via the Metadata API.
        // This is the first step in the Metadata API portion of the process.
        MdPort service = new MdPort();
        service.SessionHeader = new SessionHeader_element();
        service.SessionHeader.sessionId = UserInfo.getSessionId();
        String psName = [SELECT Name FROM PermissionSet WHERE Id =: psId LIMIT 1].Name;
        detailedDebug('Retrieving PermissionSet ' + psName + ' ('+psId+')');
        PermissionSet_x ps = null;
        try {
            ReadMetadataResult res = service.readMetadata('PermissionSet', new String[] { psName });
            if (res.IsError && res?.e?.getMessage().contains('IO Exception: Read timed out')){
                Status = 'Read timed out, trying again';
                debug(Status);
                UpdatePSAllFieldsAllObjectsQueueable aaq = new UpdatePSAllFieldsAllObjectsQueueable(Instruction, 0, RecordsPerQueueable, PermissionSetId, EnableWrite, null);
                System.enqueueJob(aaq);
            } else {
                ps = (PermissionSet_x) res.result.getRecords()[0];
            }
            
            //ps = (PermissionSet_x)service.readMetadata('PermissionSet', new String[] { psName }).getRecords()[0];
        } catch (MetadataServiceException e){

            debug('Error; Message='+e.getMessage());
            throw e;

            
        }
        return ps;
    }
  
    /***********************************
    *   PUSHUPDATEDPERMISSIONSETVIAMDAPI
     **********************************/
    private void pushUpdatedPermissionSetViaMdApi(Permissionset_x ps){
        // Saves the updated PermissionSet via the Metadata API.
        // Largely cribbed from https://github.com/certinia/apex-mdapi/blob/master/apex-mdapi/src/classes/MetadataServiceExamples.cls
        MdPort service = getMetadataApiService();
        try {
            debug('Saving...');
            List<SaveResult> results =
                    service.updateMetadata(
                        new Metadata_x[] { ps });
                        detailedDebug(json.serializePretty(results));
            for (SaveResult sr : results){
                handleSaveResults(sr, ps);
            }
        } catch (CalloutException e){
            debug('MESSAGE: ' + e.getMessage());
            debug('stack Trace ' +e.getStackTraceString());
            throw e;
        }
        debug('Successfully updated the PermissionSet.');
    }


    public static void handleSaveResults(SaveResult saveResult, PermissionSet_x ps)
    {
        // Processes the save result.
        // Largely cribbed from https://github.com/certinia/apex-mdapi/blob/master/apex-mdapi/src/classes/MetadataServiceExamples.cls    

        // Nothing to see?
        if(saveResult==null || saveResult.success){
            detailedDebug('This saveResult was a Success');
            return;
        }
           
        // Construct error message and throw an exception
        if(saveResult.errors!=null)
        {
            List<String> messages = new List<String>();
            messages.add(
                (saveResult.errors.size()==1 ? 'Error ' : 'Errors ') +
                    'occured processing component ' + saveResult.fullName + '.');
            for(Error error : saveResult.errors)
                messages.add(
                    error.message + ' (' + error.statusCode + ').' +
                    ( error.fields!=null && error.fields.size()>0 ?
                        ' Fields ' + String.join(error.fields, ',') + '.' : '' ) );
            if(messages.size()>0)
                throw new MetadataServiceException(String.join(messages, ' '));
        }
        if(!saveResult.success){
            detailedDebug('\n\nps.ApexClassPermissions: ' +JSON.serializePretty(ps.classAccesses));
            detailedDebug('\n\nps.ApexPagePermissions: ' +JSON.serializePretty(ps.pageAccesses));
            detailedDebug('\n\nps.RecordtypeAccesses: ' +JSON.serializePretty(ps.recordTypeVisibilities));
            detailedDebug('\n\nps.App Accesses: ' + JSON.serializePretty(ps.applicationVisibilities));
            throw new MetadataServiceException('Request failed with no specified error.');
        }
    }

    public class MetadataServiceException extends Exception { }

    private PermissionSet_x addApexClassPermissions(PermissionSet_x ps){
        // Go to through the existing Apex class permissions and log them, so we can skip adding them
        // This can cause errors on update if we try to update permission that already exists.
        if (ps.classAccesses == null){
            ps.classAccesses = new List<PermissionSetApexClassAccess_x>();
        }

        // Query for all Apex Classes in the system, applying our exclusions
        String nsExclusions =' NamespacePrefix NOT IN : ApexClassNamespaceExclusions AND NamespacePrefix NOT IN : GlobalNamespaceExclusions';
        if (GlobalNamespaceExclusions.contains('*') || ApexClassNamespaceExclusions.contains('*')){
            nsExclusions = ' NamespacePrefix = null';
        }
        List<ApexClass> classes = (List<ApexClass>)Database.query('SELECT Id, Name FROM ApexClass WHERE NamespacePrefix = null and LengthWithoutComments > 0 AND IsValid = true AND Status=\'Active\' and Name NOT IN : ApexClassExclusions AND ' + nsExclusions);

        // Need to track what access already exists, because we can inadvertently add duplicates to
        // the list, which may irretrievably break the Permission Set
        Set<String> existingAccess = new Set<String>();
        for (PermissionSetApexClassAccess_x existingPerm : ps.classAccesses){
            existingAccess.add(existingPerm.apexClass);
        }
        detailedDebug('Existing Access ' + existingAccess);
        // For each Class we queried...
        for (ApexClass ac : classes){
            // If access does not already exist...
            if (!existingAccess.contains(ac.Name)){
                // Create a new permission...
                PermissionSetApexClassAccess_x perm  = new PermissionSetApexClassAccess_x();
                perm.enabled = true;
                perm.apexClass = ac.Name;
                // and add it to the master Permission Set.
                ps.classAccesses.add(perm);
            }
        }
        return ps;
    }

    private PermissionSet_x addApexPagePermissions(PermissionSet_x ps){
        // If there are no pre-existing Apex Page permissions in the PermissionSet,
        // Create a List to hold them.
        if (ps.pageAccesses == null){
            ps.pageAccesses = new List<PermissionSetApexPageAccess_x>();
        }

        // Query for all Apex Pages in the system, applying our exclusions
        String nsExclusions =' NamespacePrefix NOT IN : ApexPageNamespaceExclusions AND NamespacePrefix NOT IN : GlobalNamespaceExclusions';
        if (GlobalNamespaceExclusions.contains('*') || ApexPageNamespaceExclusions.contains('*')){
            nsExclusions = ' NamespacePrefix = null';
        }
        List<ApexPage> pages = (List<ApexPage>) Database.query('SELECT Id, Name FROM ApexPage WHERE Name NOT IN : ApexPageExclusions AND ' + nsExclusions);
        detailedDebug('Adding Permissions to ' + pages.size() + ' Apex Pages');
        // Need to track what access already exists, because we can inadvertently add duplicates to
        // the list, which may irretrievably break the Permission Set
        Set<String> existingAccess = new Set<String>();
        for (PermissionSetApexPageAccess_x perm : ps.pageAccesses){
            existingAccess.add(perm.apexPage);
        }
        detailedDebug('Existing Apex PAGE Access ' + existingAccess?.size());
        List<String> skipped = new List<String>();


        // For each Page we queried..
        for (ApexPage ap : pages){
            // If access doesn't already exist...
            if (!existingAccess.contains(ap.Name)){
                // Create a new permission
                PermissionSetApexPageAccess_x perm  = new PermissionSetApexPageAccess_x();
                perm.enabled = true;
                perm.apexPage = ap.Name;
                // And add the new one to the list in the Permission Set
                ps.pageAccesses.add(perm);
            } else {
                skipped.add(ap.Name);
            }
            
        }
        detailedDebug('Skipped Apex Pages ('+skipped?.size()+') -> ' + String.join(skipped,', '));
        return ps;
    }

    private PermissionSet_x addCustomAppPermissions(PermissionSet_x ps){
        // If there are no pre-existing App permissions in the PermissionSet,
        // Create a List to hold them inside the master PermissionSet.
        if (ps.applicationVisibilities == null){
            ps.applicationVisibilities = new List<PermissionSetApplicationVisibility_x>();
        }

        // Need to track what access already exists, because we can inadvertently add duplicates to
        // the list, which may irretrievably break the Permission Set
        Set<String> existingAccess = new Set<String>();
        for (PermissionSetApplicationVisibility_x perm: ps.applicationVisibilities){
            existingAccess.add(perm.application.toLowerCase());
        }
        
        // Query for all Custom Apps in the system, applying our exclusions
        String nsExclusions =' NamespacePrefix NOT IN : CustomAppNamespaceExclusions AND NamespacePrefix NOT IN : GlobalNamespaceExclusions';
        if (GlobalNamespaceExclusions.contains('*') || CustomAppNamespaceExclusions.contains('*')){
            nsExclusions = ' NamespacePrefix = null';
        }
        List<AppDefinition> apps = (List<AppDefinition>) Database.Query('SELECT Id, Label, MasterLabel, DeveloperName, NamespacePrefix FROM AppDefinition WHERE  DeveloperName NOT IN : CustomAppExclusions AND '+ nsExclusions);
        List<String> skipped = new List<String>();
        // For each App we queried..
        for (AppDefinition ad : apps){
            // If access doesn't already exist...
            if (!existingAccess.contains(ad.DeveloperName.toLowerCase())){
                // Create a new permission
                PermissionSetApplicationVisibility_x av = new PermissionSetApplicationVisibility_x();
                av.application = (ad.NamespacePrefix != null ? ad.NamespacePrefix + '__' : '') + ad.DeveloperName;
                av.visible = true;
                // and add it to the master Permission Set.
                ps.applicationVisibilities.add(av);
            } else {
                skipped.add(ad.DeveloperName);
            }
        }
        detailedDebug('Skipped Apps: ' + String.join(skipped,', '));
        return ps;
    }

    public PermissionSet_x addRecordTypePermissions(PermissionSet_x ps){
        // If there are no pre-existing RT permissions in the PermissionSet,
        // Create a List to hold them inside the master PermissionSet.
        if (ps.recordTypeVisibilities == null){
            ps.recordTypeVisibilities = new List<PermissionSetRecordTypeVisibility_x>();
        }

        // Need to track what access already exists, because we can inadvertently add duplicates to
        // the list, which may irretrievably break the Permission Set
        Set<String> existingAccess = new Set<String>();
        for (PermissionSetRecordTypeVisibility_x perm : ps.recordTypeVisibilities){
            existingAccess.add(perm.recordType.toLowerCase());
        }

        // Query for all Record Types in the system, applying our exclusions
        String nsExclusions =' NamespacePrefix NOT IN : RecordTypeNamespaceExclusions AND NamespacePrefix NOT IN : GlobalNamespaceExclusions';
        if (GlobalNamespaceExclusions.contains('*') || RecordTypeNamespaceExclusions.contains('*')){
            nsExclusions = ' NamespacePrefix = null';
        }
        List<RecordType> recordTypes = (List<RecordType>) Database.query('SELECT Id, DeveloperName, SobjectType FROM RecordType WHERE SobjectType NOT IN : GlobalObjectExclusions and sObjectType NOT IN : RecordTypeObjectExclusions AND ' + nsExclusions);
        List<String> skipped = new List<String>();
        
        // For each RT we queried..
        for (RecordType rt :recordTypes){
            // In the RecordType table, the object name and the Record Type name are in separate fields
            // Need to concatenate them together to make the key that matches format expected by the
            // Metadata API.
            String rtKey = (rt.sObjectType + '.' + rt.DeveloperName).toLowerCase();
            // If access doesn't already exist...
            if (!existingAccess.contains(rtKey)){
                // Create a new permission
                PermissionSetRecordTypeVisibility_x rtv = new PermissionSetRecordTypeVisibility_x();
                rtv.RecordType = rt.sObjectType + '.' + rt.DeveloperName;
                rtv.visible = true;
                // and add it to the master Permission Set.
                ps.RecordTypeVisibilities.add(rtv);
            } else {
                skipped.add(rtKey);
            }   
        }
        detailedDebug('Skipped Record Types Due to Pre-Existing Access: ' + String.join(skipped,', '));
        return ps;
    }

    public MdPort getMetadataApiService(){
        MdPort service = new MdPort();
        service.SessionHeader = new SessionHeader_element();
        service.SessionHeader.sessionId = UserInfo.getSessionId();
        service.timeout_x = 120000;
        return service;
    }

    /* ##################################################################################################################################
    *                                                    PART 2: PERMISSIONS TO ADD VIA DML
    ################################################################################################################################## */
    

    /***********************************
     * DMLPROCESS
     **********************************/
    public void dmlProcess(List<String> objectNames){
        // This is the main process for a given chunk of Object/Field permissions.
        Status = 'dmlProcess() is Starting.' + toString(objectNames);
        System.debug(Status);
        Map<String,Map<String,FieldInfo>> fieldInfo = buildFieldInfo(objectNames);
        if (fieldInfo == null){
            // No more Objects to process
            return;
        }
        Map<String,PermissionPackage> permInfo = getExistingPermissions(objectNames, fieldInfo);
        permInfo = buildObjectPermissions(permInfo);
        permInfo = addTabPermissions(permInfo);
        permInfo = buildFieldPermissions(permInfo, fieldInfo);
        for (PermissionPackage pp : permInfo.values()){
            System.debug('\n\nFINAL PP\n'+pp);
        }
        List<ObjectPermissions> opToUpdate = new List<ObjectPermissions>();
        List<FieldPermissions> fpToUpdate = new List<FieldPermissions>();
        List<PermissionSetTabSetting> pstsToUpdate = new List<PermissionSetTabSetting>();
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
            if (!pp.HasPreexistingTabSetting){
                if (!pp.HasPreexistingTabSetting){
                    pstsToUpdate.add(pp.TabVisibility);
                }
            }
                
        }
        
        try {
            debug('Upserting ' + pstsToUpdate.size() + ' PermissionSetTabSetting Records');
            List<Database.UpsertResult> results = Database.upsert(pstsToUpdate, false);
            debug(JSON.serializePretty(results));
        } catch (Exception e){
            debug(e.getMessage());
            throw new DMLException('Unable to Perform DML Operation on PermissionSetTabSetting : ' +e.getMessage());
        }
        try {
            debug('Upserting ' + opToUpdate.size() + ' ObjectPermissions Records');
            List<Database.UpsertResult> results = Database.upsert(opToUpdate, false);
            
        } catch (Exception e){
            debug(e.getMessage());
            throw new DMLException('Unable to Perform DML Operation on ObjectPermissions : ' +e.getMessage());
        }
        try {
            debug('Upserting ' + fpToUpdate.size() + ' FieldPermissions Records');
            List<Database.UpsertResult> results = Database.upsert(fpToUpdate, false);
            
        } catch (Exception e){
            debug(e.getMessage());
            throw new DMLException('Unable to Perform DML Operation on FieldPermissions : ' +e.getMessage());
        }
        
        
    }

    /***********************************
     * BUILD OBJECT LIST
     **********************************/
    public List<String> buildObjectList(){
        List<String> objectNames = new List<String>();
        if (Iteration == 0)
            objectNames.addAll(ProcessFirst);
        Integer offset = Iteration * RecordsPerQueueable;

        
        String query = getBaseEntityDefinitionQuery() + '  LIMIT :RecordsPerQueueable OFFSET : offset';
        
        List<EntityDefinition> entityDefinitions = new List<EntityDefinition>();
        Map<String, Object> nameBind = new Map<String, Object>{'RecordsPerQueueable' => RecordsPerQueueable, 'offset' => offset, 'GlobalNamespaceExclusions' => GlobalNamespaceExclusions, 'GlobalObjectExclusions' => GlobalObjectExclusions};
        Status = '\nFiring query: ' + query + '\n LIMIT ' + RecordsPerQueueable + ' OFFSET ' + offset + '\nBindings:\n'+nameBind;
        debug(Status);
        try {
            entityDefinitions = (List<EntityDefinition>) Database.queryWithBinds(query,nameBind,AccessLevel.SYSTEM_MODE);
        } catch (UpdatePSException e) {
            debug(e.getMessage());
            throw e;
        }
        
        Status = 'Query returned ' + entityDefinitions?.size() + ' records';
        debug(Status);
        // If the query doesn't return anything, the process dies.
        if (entityDefinitions.size() == 0){
            debug('No more objects to process. Exiting.');
            insert new Task(OwnerId = UserInfo.getUserId(), Subject = 'All Objects / All Fields Process has Completed');
            return null;
        }
        // Simplify to a list of object names.
        for (EntityDefinition ed : entityDefinitions){
            
            // If it is on the ProcessFirst list, it was added when the list was created at the top of this method.
            Boolean processFirstContains = ProcessFirst.contains(ed.QualifiedApiName.toLowerCase());
            Boolean isCustomizable = ed.isCustomizable;
            Boolean isPlatformEvent = ed.QualifiedAPIName.endsWith('__e');
            Boolean isGlobalObjectExclusion = GlobalObjectExclusions.contains(ed.QualifiedApiName.toLowerCase());
            Boolean isNamespaceExclusion = GlobalNamespaceExclusions.contains(ed?.NamespacePrefix?.toLowerCase()) || GlobalNamespaceExclusions?.contains('*');
            Boolean addObject = (isCustomizable || isPlatformEvent) && !isNamespaceExclusion && !isGlobalObjectExclusion && !processFirstContains;
            Status = 'Object '+ ed.QualifiedAPIName + ': Adding= '+addObject+' // processFirstContains=' + processFirstContains + ' isCustomizable=' + isCustomizable + ' isPlatformEvent=' + isPlatformEvent +  ' isGlobalObjectExclusion=' + isGlobalObjectExclusion + + ' isNamespaceExclusion=' + isNamespaceExclusion;
            debug(Status);
            if (addObject){
                if (ObjectNameReplacements.containsKey(ed.QualifiedApiName.toLowerCase())){
                    objectNames.add(ObjectNameReplacements.get(ed.QualifiedApiName.toLowerCase()));
                } else {
                    objectNames.add(ed.QualifiedApiName.toLowerCase());
                }
            } 
        }
        debug('After paring down, will process ' + objectNames.size() + ' Objects in this iteration.');
        return objectNames;
    }

    /***********************************
     * GET BASE ENTITY DEFINITION QUERY
     **********************************/
    public String getBaseEntityDefinitionQuery(){
        // This is common to two queries in this process.
        // the main process appends the OFFSET and LIMIT, so using the Database.query method rather than [] notation.
        
        // NOTE: EntityDefinition does NOT support IN clauses. If you do IN : {some list or set} it will fail inelegantly without an error message.
        return 'SELECT QualifiedApiName, IsCustomizable, NamespacePrefix FROM EntityDefinition WHERE (NOT(QualifiedAPIName LIKE \'%__mdt\')) AND (NOT(QualifiedAPIName LIKE \'%__Tag\')) AND (NOT(QualifiedAPIName LIKE \'%__Share\')) AND (NOT(QualifiedAPIName LIKE \'%__ChangeEvent\')) AND (NOT(QualifiedAPIName LIKE \'%__History\')) AND (NOT(QualifiedAPIName LIKE \'%__Feed\')) AND (NOT(QualifiedAPIName LIKE \'%__VoteStat\')) AND (NOT(QualifiedAPIName LIKE \'%__ViewStat\')) AND (NOT(QualifiedAPIName LIKE \'%__DataCategorySelection\')) order by QualifiedApiName ';
        
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
                detailedDebug(Status);
                FieldInfo fi = new FieldInfo(
                    fieldName,
                    fields.get(fieldName.toLowerCase()).getDescribe().isUpdateable(),
                    fields.get(fieldName.toLowerCase()).getDescribe().isCalculated(),
                    auditFields.contains(fieldName.toLowerCase()),
                    EnableWrite
                );
                detailedDebug('FieldInfo: '+objectName+'.'+fieldName+': isUpdateable ' + fi.isUpdateable + '; IsFormula ' + fi.IsFormula + '; auditField ' + fi.IsAuditField);
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
            detailedDebug(Status);
            // Create the PermissionPackage if necessary. The constructor sets the ParentId of the ObjectPermissions to the PermissionSetId.
            if (permInfo.get(op.sObjectType.toLowerCase()) == null){
                permInfo.put(op.sObjectType.toLowerCase(), new PermissionPackage(op.sObjectType, permissionSetId));
            }

            // Pull the ObjectPermissions from the PermissionPackage, 
            // assign the ObjectPermissions we just queried, and put it back in the permInfo object.
            PermissionPackage pp = permInfo.get(op.sObjectType.toLowerCase());
            pp.ObjectPermission = op;
            pp.HasPreexistingObjectPermissions=true;
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
            detailedDebug('Looking for replacementKey ' + replacementKey + ' in ' + FieldNameReplacements.keySet());
            if (FieldNameReplacements.containsKey(replacementKey)){
                Status = 'Replacing Field Name : ' + replacementKey;
                fieldNameOnly = FieldNameReplacements.get(replacementKey);
                detailedDebug('Replaced field name for ' + perm.Field + ' to ' + FieldNameReplacements.get(replacementKey));
            } 

            if (permInfo.get(fieldNameOnly.toLowerCase()) == null){
                permInfo.put(fieldNameOnly.toLowerCase(),new PermissionPackage(perm.sObjectType.toLowerCase(),PermissionSetId));
            }
            PermissionPackage thisPP = permInfo.get(fieldNameOnly.toLowerCase());
            thisPP.HasPreexistingFieldPermissions=true;
            permInfo.put(fieldNameOnly.toLowerCase(),thisPP);
            // If it's not possible to even read the field, we don't want to add it to the FieldPermission Map in the PermissionPackage.
            Status = 'Reading existing FieldPermissions from fieldInfo for ' +perm?.sObjectType + '. ' + perm?.Field + '. fieldNameOnly: ' + fieldNameOnly + '. fieldInfo?.get((perm?.sObjectType.toLowerCase())) is Null? ' + (fieldInfo?.get((perm?.sObjectType.toLowerCase()))==null) + '. fieldInfo?.get((perm?.sObjectType.toLowerCase()))?.get(fieldNameOnly?.toLowerCase()) Is Null? ' + (fieldInfo?.get((perm?.sObjectType.toLowerCase()))?.get(fieldNameOnly?.toLowerCase())==null);
            detailedDebug(Status);
            if (fieldInfo?.get((perm?.sObjectType.toLowerCase()))?.get(fieldNameOnly?.toLowerCase())==null){
                detailedDebug (JSON.serializePretty(perm));
                detailedDebug(JSON.serializePretty(fieldInfo));
            }
            Boolean addField = fieldInfo?.get((perm?.sObjectType.toLowerCase()))?.get(fieldNameOnly?.toLowerCase())?.EnableRead;
            if (addField){
                // Just to be safe, if we don't have a PermissionPackage for this object yet, create it.
                if (permInfo.get(perm.sObjectType.toLowerCase()) == null){
                    detailedDebug('addExistingFieldPermissions: Creating new PP for '+perm.sObjectType.toLowerCase());
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
                Status = 'Adding existing FieldPermissions to the permInfo object for '+perm?.sObjectType + '.' + perm?.Field;
                detailedDebug(Status);
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
                // If we're here, we missed setting up the object permissions above.
                detailedDebug('addNewObjectsAndFields: Creating new PP for '+objectName.toLowerCase());
                permInfo.put(objectName.toLowerCase(),new PermissionPackage(objectName.toLowerCase(), permissionSetId));
            }
            PermissionPackage thisPP = permInfo.get(objectName.toLowerCase());
            thisPP = buildSingleObjectPermissions(thisPP);
            permInfo.put(objectName.toLowerCase(), thisPP);
            
            
            if (!permInfo.get(objectName.toLowerCase()).IsPlatformEvent){
                Map<String, Schema.SObjectField> fields = globalDescribe.get(objectName.toLowerCase()).getDescribe().fields.getMap();
                for(String fieldName : fields.keyset() ){
                    // Field name comes back from the schema as the field name only (no object name prepended) and all lower case.
                    // Use the fieldInfo package 
                    // Since we processed object level first, we can assume there is a PermissionPackage for this object.
                    PermissionPackage pp = permInfo.get(objectName.toLowerCase());
                    Status = 'Creating a blank FieldPermissions for ' + objectName + ' / ' + fieldName;
                    detailedDebug(Status);
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
            detailedDebug('buildObjectPermissions: Adding Existing ObjectPermissions For ' + pPkg.ObjectName.toLowerCase());
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
        Status = 'pp is null? ' + (pp == null ? true : false);
        detailedDebug(Status);
        Status = 'buildSingleObjectPermissions: Building Object Permissions for ' + pp?.ObjectName;
        debug(Status);
        if (pp.ObjectPermission.sObjectType == null){
            pp.ObjectPermission.sObjectType = pp.ObjectName;
        }
        if (pp.ObjectPermission?.PermissionsRead == null || !pp.ObjectPermission.PermissionsRead){
            pp.ObjectPermission.PermissionsRead = true;
            pp.IsObjectPermissionDirty = true;
        }
        if (EnableWrite && (pp.ObjectPermission.PermissionsCreate == null || !pp.ObjectPermission.PermissionsCreate)) {
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
            if (EnableWrite && (pp.ObjectPermission.PermissionsDelete == null || !pp.ObjectPermission.PermissionsDelete)) {
                pp.ObjectPermission.PermissionsDelete = true;
                pp.IsObjectPermissionDirty = true;
            }
            
            if (EnableWrite && (pp.ObjectPermission.PermissionsEdit == null || !pp.ObjectPermission.PermissionsEdit)) {
                pp.ObjectPermission.PermissionsEdit = true;
                pp.IsObjectPermissionDirty = true;
            }
            if (EnableWrite && (pp.ObjectPermission.PermissionsModifyAllRecords == null || !pp.ObjectPermission.PermissionsModifyAllRecords)) {
                pp.ObjectPermission.PermissionsModifyAllRecords = true;
                pp.IsObjectPermissionDirty = true;
            }
        }
        
        return pp;
    }

    /***********************************
     * ADD TAB PERMISSIONS
     **********************************/
    private Map<String,PermissionPackage> addTabPermissions(Map<String,PermissionPackage> permInfo){
        List<String> pstsNames = new List<String>();
        for (PermissionPackage pp : permInfo.values()){
            // In this table, standard object names are prepended with 'standard'
            if (pp.ObjectType == 'standard'){
                pstsNames.add((pp.ObjectType == 'standard' ? 'standard-' : '') + pp.ObjectName.toLowerCase());
            } else {
                pstsNames.add(pp.ObjectName.toLowerCase());
            }
            
        }
        Set<String> pstsExists = new Set<String>();
        // Pull the existing Tab Settings for the in-cope objects.
        // If there is already a tab setting, set the flag in the PermissionPackage
        // Later on, we won't attempt to upsert the PermissionSetTabSetting for this object if there is a preexisting one.
        for (PermissionSetTabSetting psts: [SELECT Id, Name FROM PermissionSetTabSetting WHERE ParentId = :PermissionSetId AND Name IN : pstsNames]){
            Status = 'Setting pstsExists to TRUE  For ' + psts.Name;
            detailedDebug(Status);
            // The Name field contains the object name, but standard objects are prepended with 'standard-', so strip that out
            String objectName = psts.Name.replace('standard-','').toLowerCase();
            pstsExists.add(objectName);
        }

        // Go through all the objects in the permList. If there is NOT a preexisting Tab permission,
        // Add one.
        // Note: If there is not a Tab for this object, we can still add it. When we upsert later,
        // we allow partial success. So any objects that do not have a Tab will fail,
        // but we will still be able to insert the permissions for others.
        Map<String,PermissionPackage> out = new Map<String,PermissionPackage>();
        for (PermissionPackage pp : permInfo.values()){
            detailedDebug('pstsExists.contains + ' +pstsExists.contains(pp.ObjectName.toLowerCase()));
            pp.HasPreexistingTabSetting = pstsExists.contains(pp.ObjectName.toLowerCase());
            if (!pstsExists.contains(pp.ObjectName.toLowerCase())){
                pp.TabVisibility=new PermissionSetTabSetting(
                    Name = pp.TabPermissionName,
                    Visibility = 'DefaultOff',
                    ParentId = PermissionSetId
                );
            }
            out.put(pp.ObjectName.toLowerCase(),pp);
        }
        return out;
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
       
        Boolean isDirty=false;
        Status = 'Setting field permissions for ' + fp.Field + ' / SetRead: ' + fieldInfo.EnableRead + ' / Existing PermissionsRead: ' + fp.PermissionsRead;
        detailedDebug(Status);
        if ((fieldInfo.EnableRead) && (fp.PermissionsRead == null || fp.PermissionsRead == false)){
            fp.PermissionsRead = true;
            isDirty=true;
        }
        // Don't attempt to write Edit permissions to formulas.
        Status = 'Setting field permissions for ' + fp.Field + ' / SetRead: ' + fieldInfo.EnableUpdate + ' / Existing PermissionsEdit: ' + fp.PermissionsEdit;
        detailedDebug(Status);
        if (fieldInfo.EnableUpdate && (fp.PermissionsEdit == null || fp.PermissionsEdit == false)){
            fp.PermissionsEdit = true;
            isDirty=true;
        }
        
        
        return new FieldPermissionInfo(fp,isDirty);
    }

    /***********************************
     * TOSTRING
     **********************************/
    public override String toString(){
        String out = '\n\nUpdatePSAllFieldsAllObjectsQueueable\n';
        out += 'Iteration: ' + Iteration + '\n';
        out += 'PermissionSetId ' +  PermissionSetId + '\n';
        out += 'RecordsPerQueueable (Query Limit / Qty Objects to Process In This Batch): ' +  RecordsPerQueueable+ '\n';
        out += 'TotalObjectsThisIteration: ' +  TotalObjectsThisIteration+ '\n';
        out += 'Query Offset: ' + (RecordsPerQueueable * Iteration)+ '\n';
        out += 'Max Iterations: ' + (MaxIterations == -1 ? 'All' : (MaxIterations == 0 ? 'This Batch Only' : (String.valueOf(MaxIterations)))) + '\n';
        out += 'EnableWrite Permissions: ' +  EnableWrite+ '\n';
        out += 'Qty FieldNameReplacements: ' + FieldNameReplacements?.size()+ '\n';
        out += 'Qty ObjectNameReplacements: ' +  ObjectNameReplacements?.size()+ '\n';
        out += 'Qty ObjectExclusions: ' +  GlobalObjectExclusions?.size()+ '\n';
        out += 'Qty NamespaceExclusions: ' +  GlobalNamespaceExclusions?.size()+ '\n';
        out += 'Most Recent Status Trace: ' + Status + '\n';
        return out;
    }

    public string toString(List<String> objects){
        return toString() + 'Objects In Scope This Iteration: ' + String.join(objects,', ')+ '\n';
    }

    public static void debug(String msg){
        if (EnableDebug){
            System.debug('###'+msg);
        }
    }

    public static void detailedDebug(String msg){
        if (EnableVerboseDebug){
            System.debug('#####'+msg);
        }
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
        public PermissionSetTabSetting TabVisibility {get;set;}
        public Boolean IsPlatformEvent {get;set;}
        public Boolean HasPreexistingTabSetting {get;set;}
        public Boolean HasPreexistingObjectPermissions {get;set;}
        public Boolean HasPreexistingFieldPermissions {get;set;}
        public String ObjectType { get {
            if (ObjectName != null){
                if (ObjectName.endsWithIgnoreCase('__c')){
                    return 'custom';
                } else if (ObjectName.endsWithIgnoreCase('__e')){
                    return 'platformevent';
                } 
                return 'standard';
            } else {
                return null;
            }
        }}
        // Returns the name of the object as represented in the Name field of the 
        // PermissionSetTabVisibility object. If standard object, need to prepend "standard-"
        public String TabPermissionName { get {
            return (ObjectType == 'standard' ? 'standard-' : '' ) + ObjectName;
        }}

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
            HasPreexistingTabSetting=false;
            HasPreexistingFieldPermissions=false;
            HasPreexistingObjectPermissions=false;
        }
        public override String toString(){
            return '\n\nPermissionPackage:\n'+JSON.serializePretty(this);
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
        public Boolean EnableWrite {get;set;} // This is the global setting to enable write access
        public Boolean EnableRead { get {
            // No scenarios found where we would not want to apply read permission.
            return true;
        }}
        public Boolean EnableUpdate { get {
            return !IsAuditField && IsUpdateable && !IsFormula && EnableWrite;
        
        }}

        public FieldInfo(String fName, Boolean isUpdate, Boolean isForm, Boolean isAudit, Boolean ew){
            Name = fName.toLowerCase();
            IsFormula = isForm;
            IsUpdateable = isUpdate;
            IsAuditField = isAudit;
            EnableWrite = ew;
        }

        
    }

    public Class UpdatePSException extends Exception {}

    /* ##################################################################################################################################
    *                                                     METADATA API SERVICE METHODS
    ################################################################################################################################## */
    
    // From https://github.com/certinia/apex-mdapi/tree/master


        
        public static final String SOAP_M_URI = 'http://soap.sforce.com/2006/04/metadata';

        public class PermissionSet_x extends Metadata_x {
            public String type = 'PermissionSet';
            public String fullName;
            private String[] fullName_type_info = new String[]{'fullName',SOAP_M_URI,null,'0','1','false'};
            public PermissionSetApplicationVisibility_x[] applicationVisibilities;
            public PermissionSetApexClassAccess_x[] classAccesses;
            public PermissionSetCustomPermissions_x[] customPermissions;
            public String description;
            public PermissionSetExternalDataSourceAccess_x[] externalDataSourceAccesses;
            public PermissionSetFieldPermissions_x[] fieldPermissions;
            public Boolean hasActivationRequired;
            public String label;
            public String license;
            public PermissionSetObjectPermissions_x[] objectPermissions;
            public PermissionSetApexPageAccess_x[] pageAccesses;
            public PermissionSetRecordTypeVisibility_x[] recordTypeVisibilities;
            public PermissionSetTabSetting_x[] tabSettings;
            public PermissionSetUserPermission_x[] userPermissions;
            private String[] applicationVisibilities_type_info = new String[]{'applicationVisibilities',SOAP_M_URI,null,'0','-1','false'};
            private String[] classAccesses_type_info = new String[]{'classAccesses',SOAP_M_URI,null,'0','-1','false'};
            private String[] customPermissions_type_info = new String[]{'customPermissions',SOAP_M_URI,null,'0','-1','false'};
            private String[] description_type_info = new String[]{'description',SOAP_M_URI,null,'0','1','false'};
            private String[] externalDataSourceAccesses_type_info = new String[]{'externalDataSourceAccesses',SOAP_M_URI,null,'0','-1','false'};
            private String[] fieldPermissions_type_info = new String[]{'fieldPermissions',SOAP_M_URI,null,'0','-1','false'};
            private String[] hasActivationRequired_type_info = new String[]{'hasActivationRequired',SOAP_M_URI,null,'0','1','false'};
            private String[] label_type_info = new String[]{'label',SOAP_M_URI,null,'1','1','false'};
            private String[] license_type_info = new String[]{'license',SOAP_M_URI,null,'0','1','false'};
            private String[] objectPermissions_type_info = new String[]{'objectPermissions',SOAP_M_URI,null,'0','-1','false'};
            private String[] pageAccesses_type_info = new String[]{'pageAccesses',SOAP_M_URI,null,'0','-1','false'};
            private String[] recordTypeVisibilities_type_info = new String[]{'recordTypeVisibilities',SOAP_M_URI,null,'0','-1','false'};
            private String[] tabSettings_type_info = new String[]{'tabSettings',SOAP_M_URI,null,'0','-1','false'};
            private String[] userPermissions_type_info = new String[]{'userPermissions',SOAP_M_URI,null,'0','-1','false'};
            private String[] apex_schema_type_info = new String[]{SOAP_M_URI,'true','false'};
            private String[] type_att_info = new String[]{'xsi:type'};
            private String[] field_order_type_info = new String[]{'fullName', 'applicationVisibilities','classAccesses','customPermissions','description','externalDataSourceAccesses','fieldPermissions','hasActivationRequired','label','license','objectPermissions','pageAccesses','recordTypeVisibilities','tabSettings','userPermissions'};
        }
        public class PermissionSetApplicationVisibility_x {
            public String application;
            public Boolean visible;
            private String[] application_type_info = new String[]{'application','http://soap.sforce.com/2006/04/metadata',null,'1','1','false'};
            private String[] visible_type_info = new String[]{'visible','http://soap.sforce.com/2006/04/metadata',null,'1','1','false'};
            private String[] apex_schema_type_info = new String[]{'http://soap.sforce.com/2006/04/metadata','true','false'};
            private String[] field_order_type_info = new String[]{'application','visible'};
        }
        public class PermissionSetApexPageAccess_x  {
            public String apexPage;
            public Boolean enabled;
            private String[] apexPage_type_info = new String[]{'apexPage','http://soap.sforce.com/2006/04/metadata',null,'1','1','false'};
            private String[] enabled_type_info = new String[]{'enabled','http://soap.sforce.com/2006/04/metadata',null,'1','1','false'};
            private String[] apex_schema_type_info = new String[]{'http://soap.sforce.com/2006/04/metadata','true','false'};
            private String[] field_order_type_info = new String[]{'apexPage','enabled'};
        }
    public class PermissionSetCustomMetadataTypeAccess_x  {
            public Boolean enabled;
            public String name;
            private String[] enabled_type_info = new String[]{'enabled','http://soap.sforce.com/2006/04/metadata',null,'1','1','false'};
            private String[] name_type_info = new String[]{'name','http://soap.sforce.com/2006/04/metadata',null,'1','1','false'};
            private String[] apex_schema_type_info = new String[]{'http://soap.sforce.com/2006/04/metadata','true','false'};
            private String[] field_order_type_info = new String[]{'enabled','name'};
        }
        public class PermissionSetCustomPermissions_x {
            public Boolean enabled;
            public String name;
            private String[] enabled_type_info = new String[]{'enabled','http://soap.sforce.com/2006/04/metadata',null,'1','1','false'};
            private String[] name_type_info = new String[]{'name','http://soap.sforce.com/2006/04/metadata',null,'1','1','false'};
            private String[] apex_schema_type_info = new String[]{'http://soap.sforce.com/2006/04/metadata','true','false'};
            private String[] field_order_type_info = new String[]{'enabled','name'};
        }
        public class PermissionSetUserPermission_x {
            public Boolean enabled;
            public String name;
            private String[] enabled_type_info = new String[]{'enabled','http://soap.sforce.com/2006/04/metadata',null,'1','1','false'};
            private String[] name_type_info = new String[]{'name','http://soap.sforce.com/2006/04/metadata',null,'1','1','false'};
            private String[] apex_schema_type_info = new String[]{'http://soap.sforce.com/2006/04/metadata','true','false'};
            private String[] field_order_type_info = new String[]{'enabled','name'};
        }
        public class PermissionSetCustomSettingAccess_x  {
            public Boolean enabled;
            public String name;
            private String[] enabled_type_info = new String[]{'enabled','http://soap.sforce.com/2006/04/metadata',null,'1','1','false'};
            private String[] name_type_info = new String[]{'name','http://soap.sforce.com/2006/04/metadata',null,'1','1','false'};
            private String[] apex_schema_type_info = new String[]{'http://soap.sforce.com/2006/04/metadata','true','false'};
            private String[] field_order_type_info = new String[]{'enabled','name'};
        }
        public class PermissionSetFlowAccess_x  {
            public Boolean enabled;
            public String flow;
            private String[] enabled_type_info = new String[]{'enabled','http://soap.sforce.com/2006/04/metadata',null,'1','1','false'};
            private String[] flow_type_info = new String[]{'flow','http://soap.sforce.com/2006/04/metadata',null,'1','1','false'};
            private String[] apex_schema_type_info = new String[]{'http://soap.sforce.com/2006/04/metadata','true','false'};
            private String[] field_order_type_info = new String[]{'enabled','flow'};
        }
        public class PermissionSetFieldPermissions_x  {
            public Boolean editable;
            public String field;
            public Boolean readable;
            private String[] editable_type_info = new String[]{'editable','http://soap.sforce.com/2006/04/metadata',null,'1','1','false'};
            private String[] field_type_info = new String[]{'field','http://soap.sforce.com/2006/04/metadata',null,'1','1','false'};
            private String[] readable_type_info = new String[]{'readable','http://soap.sforce.com/2006/04/metadata',null,'0','1','false'};
            private String[] apex_schema_type_info = new String[]{'http://soap.sforce.com/2006/04/metadata','true','false'};
            private String[] field_order_type_info = new String[]{'editable','field','readable'};
        }
        public class PermissionSetExternalDataSourceAccess_x  {
            public Boolean enabled;
            public String externalDataSource;
            private String[] enabled_type_info = new String[]{'enabled','http://soap.sforce.com/2006/04/metadata',null,'1','1','false'};
            private String[] externalDataSource_type_info = new String[]{'externalDataSource','http://soap.sforce.com/2006/04/metadata',null,'1','1','false'};
            private String[] apex_schema_type_info = new String[]{'http://soap.sforce.com/2006/04/metadata','true','false'};
            private String[] field_order_type_info = new String[]{'enabled','externalDataSource'};
        }
        public class PermissionSetRecordTypeVisibility_x  {
            public String recordType;
            public Boolean visible;
            private String[] recordType_type_info = new String[]{'recordType','http://soap.sforce.com/2006/04/metadata',null,'1','1','false'};
            private String[] visible_type_info = new String[]{'visible','http://soap.sforce.com/2006/04/metadata',null,'1','1','false'};
            private String[] apex_schema_type_info = new String[]{'http://soap.sforce.com/2006/04/metadata','true','false'};
            private String[] field_order_type_info = new String[]{'recordType','visible'};
        }
        public class PermissionSetObjectPermissions_x  {
            public Boolean allowCreate;
            public Boolean allowDelete;
            public Boolean allowEdit;
            public Boolean allowRead;
            public Boolean modifyAllRecords;
            public String object_x;
            public Boolean viewAllRecords;
            private String[] allowCreate_type_info = new String[]{'allowCreate','http://soap.sforce.com/2006/04/metadata',null,'1','1','false'};
            private String[] allowDelete_type_info = new String[]{'allowDelete','http://soap.sforce.com/2006/04/metadata',null,'1','1','false'};
            private String[] allowEdit_type_info = new String[]{'allowEdit','http://soap.sforce.com/2006/04/metadata',null,'1','1','false'};
            private String[] allowRead_type_info = new String[]{'allowRead','http://soap.sforce.com/2006/04/metadata',null,'1','1','false'};
            private String[] modifyAllRecords_type_info = new String[]{'modifyAllRecords','http://soap.sforce.com/2006/04/metadata',null,'1','1','false'};
            private String[] object_x_type_info = new String[]{'object','http://soap.sforce.com/2006/04/metadata',null,'1','1','false'};
            private String[] viewAllRecords_type_info = new String[]{'viewAllRecords','http://soap.sforce.com/2006/04/metadata',null,'1','1','false'};
            private String[] apex_schema_type_info = new String[]{'http://soap.sforce.com/2006/04/metadata','true','false'};
            private String[] field_order_type_info = new String[]{'allowCreate','allowDelete','allowEdit','allowRead','modifyAllRecords','object_x','viewAllRecords'};
        }
        public class PermissionSetApexClassAccess_x  {
            public String apexClass;
            public Boolean enabled;
            private String[] apexClass_type_info = new String[]{'apexClass','http://soap.sforce.com/2006/04/metadata',null,'1','1','false'};
            private String[] enabled_type_info = new String[]{'enabled','http://soap.sforce.com/2006/04/metadata',null,'1','1','false'};
            private String[] apex_schema_type_info = new String[]{'http://soap.sforce.com/2006/04/metadata','true','false'};
            private String[] field_order_type_info = new String[]{'apexClass','enabled'};
        }
        public class PermissionSetLicenseDefinition_x {
            public PermissionSetLicenseDefinitionCustomPermission_x[] customPermissions;
            public Boolean isSupplementLicense;
            public String label;
            public String licenseExpirationPolicy;
            public String userLicenseRestrictions;
            private String[] customPermissions_type_info = new String[]{'customPermissions','http://soap.sforce.com/2006/04/metadata',null,'0','-1','false'};
            private String[] isSupplementLicense_type_info = new String[]{'isSupplementLicense','http://soap.sforce.com/2006/04/metadata',null,'0','1','false'};
            private String[] label_type_info = new String[]{'label','http://soap.sforce.com/2006/04/metadata',null,'1','1','false'};
            private String[] licenseExpirationPolicy_type_info = new String[]{'licenseExpirationPolicy','http://soap.sforce.com/2006/04/metadata',null,'1','1','false'};
            private String[] userLicenseRestrictions_type_info = new String[]{'userLicenseRestrictions','http://soap.sforce.com/2006/04/metadata',null,'0','1','false'};
            private String[] apex_schema_type_info = new String[]{'http://soap.sforce.com/2006/04/metadata','true','false'};
            private String[] field_order_type_info = new String[]{'customPermissions','isSupplementLicense','label','licenseExpirationPolicy','userLicenseRestrictions'};
        }
        public class PermissionSetEmailRoutingAddressAccess_x  {
            public Boolean enabled;
            public String name;
            private String[] enabled_type_info = new String[]{'enabled','http://soap.sforce.com/2006/04/metadata',null,'1','1','false'};
            private String[] name_type_info = new String[]{'name','http://soap.sforce.com/2006/04/metadata',null,'1','1','false'};
            private String[] apex_schema_type_info = new String[]{'http://soap.sforce.com/2006/04/metadata','true','false'};
            private String[] field_order_type_info = new String[]{'enabled','name'};
        }
        public class PermissionSetExternalCredentialPrincipalAccess_x  {
            public Boolean enabled;
            public String externalCredentialPrincipal;
            private String[] enabled_type_info = new String[]{'enabled','http://soap.sforce.com/2006/04/metadata',null,'1','1','false'};
            private String[] externalCredentialPrincipal_type_info = new String[]{'externalCredentialPrincipal','http://soap.sforce.com/2006/04/metadata',null,'1','1','false'};
            private String[] apex_schema_type_info = new String[]{'http://soap.sforce.com/2006/04/metadata','true','false'};
            private String[] field_order_type_info = new String[]{'enabled','externalCredentialPrincipal'};
        }
        public class PermissionSetTabSetting_x  {
            public String tab;
            public String visibility;
            private String[] tab_type_info = new String[]{'tab','http://soap.sforce.com/2006/04/metadata',null,'1','1','false'};
            private String[] visibility_type_info = new String[]{'visibility','http://soap.sforce.com/2006/04/metadata',null,'1','1','false'};
            private String[] apex_schema_type_info = new String[]{'http://soap.sforce.com/2006/04/metadata','true','false'};
            private String[] field_order_type_info = new String[]{'tab','visibility'};
        }
        
        public class MutingPermissionSet_x {
            public String label;
            private String[] label_type_info = new String[]{'label','http://soap.sforce.com/2006/04/metadata',null,'1','1','false'};
            private String[] apex_schema_type_info = new String[]{'http://soap.sforce.com/2006/04/metadata','true','false'};
            private String[] field_order_type_info = new String[]{'label'};
        }
        public class PermissionSetLicenseDefinitionCustomPermission_x  {
            public String name;
            private String[] name_type_info = new String[]{'name','http://soap.sforce.com/2006/04/metadata',null,'1','1','false'};
            private String[] apex_schema_type_info = new String[]{'http://soap.sforce.com/2006/04/metadata','true','false'};
            private String[] field_order_type_info = new String[]{'name'};
        }
        public class CustomApplication_x extends Metadata_x {
            public String type = 'CustomApplication';
            public String fullName;
            private String[] fullName_type_info = new String[]{'fullName',SOAP_M_URI,null,'0','1','false'};
            public AppActionOverride_x[] actionOverrides;
            public AppBrand_x brand;
            public ServiceCloudConsoleConfig_x consoleConfig;
            public String defaultLandingTab;
            public String description;
            public String[] formFactors;
            public Boolean isServiceCloudConsole;
            public String label;
            public String logo;
            public String navType;
            public AppPreferences_x preferences;
            public AppProfileActionOverride_x[] profileActionOverrides;
            public String setupExperience;
            public String[] subscriberTabs;
            public String[] tabs;
            public String uiType;
            public String utilityBar;
            public AppWorkspaceConfig_x workspaceConfig;
            private String[] actionOverrides_type_info = new String[]{'actionOverrides',SOAP_M_URI,null,'0','-1','false'};
            private String[] brand_type_info = new String[]{'brand',SOAP_M_URI,null,'0','1','false'};
            private String[] consoleConfig_type_info = new String[]{'consoleConfig',SOAP_M_URI,null,'0','1','false'};
            private String[] defaultLandingTab_type_info = new String[]{'defaultLandingTab',SOAP_M_URI,null,'0','1','false'};
            private String[] description_type_info = new String[]{'description',SOAP_M_URI,null,'0','1','false'};
            private String[] formFactors_type_info = new String[]{'formFactors',SOAP_M_URI,null,'0','-1','false'};
            private String[] isServiceCloudConsole_type_info = new String[]{'isServiceCloudConsole',SOAP_M_URI,null,'0','1','false'};
            private String[] label_type_info = new String[]{'label',SOAP_M_URI,null,'0','1','false'};
            private String[] logo_type_info = new String[]{'logo',SOAP_M_URI,null,'0','1','false'};
            private String[] navType_type_info = new String[]{'navType',SOAP_M_URI,null,'0','1','false'};
            private String[] preferences_type_info = new String[]{'preferences',SOAP_M_URI,null,'0','1','false'};
            private String[] profileActionOverrides_type_info = new String[]{'profileActionOverrides',SOAP_M_URI,null,'0','-1','false'};
            private String[] setupExperience_type_info = new String[]{'setupExperience',SOAP_M_URI,null,'0','1','false'};
            private String[] subscriberTabs_type_info = new String[]{'subscriberTabs',SOAP_M_URI,null,'0','-1','false'};
            private String[] tabs_type_info = new String[]{'tabs',SOAP_M_URI,null,'0','-1','false'};
            private String[] uiType_type_info = new String[]{'uiType',SOAP_M_URI,null,'0','1','false'};
            private String[] utilityBar_type_info = new String[]{'utilityBar',SOAP_M_URI,null,'0','1','false'};
            private String[] workspaceConfig_type_info = new String[]{'workspaceConfig',SOAP_M_URI,null,'0','1','false'};
            private String[] apex_schema_type_info = new String[]{SOAP_M_URI,'true','false'};
            private String[] type_att_info = new String[]{'xsi:type'};
            private String[] field_order_type_info = new String[]{'fullName', 'actionOverrides','brand','consoleConfig','defaultLandingTab','description','formFactors','isServiceCloudConsole','label','logo','navType','preferences','profileActionOverrides','setupExperience','subscriberTabs','tabs','uiType','utilityBar','workspaceConfig'};
        }
        public class AppActionOverride_x {
            public String pageOrSobjectType;
            private String[] pageOrSobjectType_type_info = new String[]{'pageOrSobjectType',SOAP_M_URI,null,'1','1','false'};
            private String[] apex_schema_type_info = new String[]{SOAP_M_URI,'true','false'};
            private String[] field_order_type_info = new String[]{'pageOrSobjectType'};
        }
        public class AppBrand_x {
            public String footerColor;
            public String headerColor;
            public String logo;
            public Integer logoVersion;
            public Boolean shouldOverrideOrgTheme;
            private String[] footerColor_type_info = new String[]{'footerColor',SOAP_M_URI,null,'0','1','false'};
            private String[] headerColor_type_info = new String[]{'headerColor',SOAP_M_URI,null,'0','1','false'};
            private String[] logo_type_info = new String[]{'logo',SOAP_M_URI,null,'0','1','false'};
            private String[] logoVersion_type_info = new String[]{'logoVersion',SOAP_M_URI,null,'0','1','false'};
            private String[] shouldOverrideOrgTheme_type_info = new String[]{'shouldOverrideOrgTheme',SOAP_M_URI,null,'0','1','false'};
            private String[] apex_schema_type_info = new String[]{SOAP_M_URI,'true','false'};
            private String[] field_order_type_info = new String[]{'footerColor','headerColor','logo','logoVersion','shouldOverrideOrgTheme'};
        }
        public class DefaultShortcut_x {
            public String action;
            public Boolean active;
            public String keyCommand;
            private String[] action_type_info = new String[]{'action',SOAP_M_URI,null,'1','1','false'};
            private String[] active_type_info = new String[]{'active',SOAP_M_URI,null,'1','1','false'};
            private String[] keyCommand_type_info = new String[]{'keyCommand',SOAP_M_URI,null,'1','1','false'};
            private String[] apex_schema_type_info = new String[]{SOAP_M_URI,'true','false'};
            private String[] field_order_type_info = new String[]{'action','active','keyCommand'};
        }
        public class ServiceCloudConsoleConfig_x {
            public AppComponentList_x componentList;
            public String detailPageRefreshMethod;
            public String footerColor;
            public String headerColor;
            public KeyboardShortcuts_x keyboardShortcuts;
            public ListPlacement_x listPlacement;
            public String listRefreshMethod;
            public LiveAgentConfig_x liveAgentConfig;
            public String primaryTabColor;
            public PushNotification_x[] pushNotifications;
            public TabLimitConfig_x tabLimitConfig;
            public String[] whitelistedDomains;
            private String[] componentList_type_info = new String[]{'componentList',SOAP_M_URI,null,'0','1','false'};
            private String[] detailPageRefreshMethod_type_info = new String[]{'detailPageRefreshMethod',SOAP_M_URI,null,'1','1','false'};
            private String[] footerColor_type_info = new String[]{'footerColor',SOAP_M_URI,null,'0','1','false'};
            private String[] headerColor_type_info = new String[]{'headerColor',SOAP_M_URI,null,'0','1','false'};
            private String[] keyboardShortcuts_type_info = new String[]{'keyboardShortcuts',SOAP_M_URI,null,'1','1','false'};
            private String[] listPlacement_type_info = new String[]{'listPlacement',SOAP_M_URI,null,'1','1','false'};
            private String[] listRefreshMethod_type_info = new String[]{'listRefreshMethod',SOAP_M_URI,null,'1','1','false'};
            private String[] liveAgentConfig_type_info = new String[]{'liveAgentConfig',SOAP_M_URI,null,'0','1','false'};
            private String[] primaryTabColor_type_info = new String[]{'primaryTabColor',SOAP_M_URI,null,'0','1','false'};
            private String[] pushNotifications_type_info = new String[]{'pushNotifications',SOAP_M_URI,null,'0','-1','false'};
            private String[] tabLimitConfig_type_info = new String[]{'tabLimitConfig',SOAP_M_URI,null,'0','1','false'};
            private String[] whitelistedDomains_type_info = new String[]{'whitelistedDomains',SOAP_M_URI,null,'0','-1','false'};
            private String[] apex_schema_type_info = new String[]{SOAP_M_URI,'true','false'};
            private String[] field_order_type_info = new String[]{'componentList','detailPageRefreshMethod','footerColor','headerColor','keyboardShortcuts','listPlacement','listRefreshMethod','liveAgentConfig','primaryTabColor','pushNotifications','tabLimitConfig','whitelistedDomains'};
        }
        public class KeyboardShortcuts_x {
            public CustomShortcut_x[] customShortcuts;
            public DefaultShortcut_x[] defaultShortcuts;
            private String[] customShortcuts_type_info = new String[]{'customShortcuts',SOAP_M_URI,null,'0','-1','false'};
            private String[] defaultShortcuts_type_info = new String[]{'defaultShortcuts',SOAP_M_URI,null,'0','-1','false'};
            private String[] apex_schema_type_info = new String[]{SOAP_M_URI,'true','false'};
            private String[] field_order_type_info = new String[]{'customShortcuts','defaultShortcuts'};
        }
        public class CustomShortcut_x {
            public String description;
            public String eventName;
            private String[] description_type_info = new String[]{'description',SOAP_M_URI,null,'0','1','false'};
            private String[] eventName_type_info = new String[]{'eventName',SOAP_M_URI,null,'1','1','false'};
            private String[] apex_schema_type_info = new String[]{SOAP_M_URI,'true','false'};
            private String[] field_order_type_info = new String[]{'description','eventName'};
        }
        public class AppComponentList_x {
            public String alignment;
            public String[] components;
            private String[] alignment_type_info = new String[]{'alignment',SOAP_M_URI,null,'1','1','false'};
            private String[] components_type_info = new String[]{'components',SOAP_M_URI,null,'0','-1','false'};
            private String[] apex_schema_type_info = new String[]{SOAP_M_URI,'true','false'};
            private String[] field_order_type_info = new String[]{'alignment','components'};
        }
        public class ListPlacement_x {
            public Integer height;
            public String location;
            public String units;
            public Integer width;
            private String[] height_type_info = new String[]{'height',SOAP_M_URI,null,'0','1','false'};
            private String[] location_type_info = new String[]{'location',SOAP_M_URI,null,'1','1','false'};
            private String[] units_type_info = new String[]{'units',SOAP_M_URI,null,'0','1','false'};
            private String[] width_type_info = new String[]{'width',SOAP_M_URI,null,'0','1','false'};
            private String[] apex_schema_type_info = new String[]{SOAP_M_URI,'true','false'};
            private String[] field_order_type_info = new String[]{'height','location','units','width'};
        }
        public class LiveAgentConfig_x {
            public Boolean enableLiveChat;
            public Boolean openNewAccountSubtab;
            public Boolean openNewCaseSubtab;
            public Boolean openNewContactSubtab;
            public Boolean openNewLeadSubtab;
            public Boolean openNewVFPageSubtab;
            public String[] pageNamesToOpen;
            public Boolean showKnowledgeArticles;
            private String[] enableLiveChat_type_info = new String[]{'enableLiveChat',SOAP_M_URI,null,'0','1','false'};
            private String[] openNewAccountSubtab_type_info = new String[]{'openNewAccountSubtab',SOAP_M_URI,null,'0','1','false'};
            private String[] openNewCaseSubtab_type_info = new String[]{'openNewCaseSubtab',SOAP_M_URI,null,'0','1','false'};
            private String[] openNewContactSubtab_type_info = new String[]{'openNewContactSubtab',SOAP_M_URI,null,'0','1','false'};
            private String[] openNewLeadSubtab_type_info = new String[]{'openNewLeadSubtab',SOAP_M_URI,null,'0','1','false'};
            private String[] openNewVFPageSubtab_type_info = new String[]{'openNewVFPageSubtab',SOAP_M_URI,null,'0','1','false'};
            private String[] pageNamesToOpen_type_info = new String[]{'pageNamesToOpen',SOAP_M_URI,null,'0','-1','false'};
            private String[] showKnowledgeArticles_type_info = new String[]{'showKnowledgeArticles',SOAP_M_URI,null,'0','1','false'};
            private String[] apex_schema_type_info = new String[]{SOAP_M_URI,'true','false'};
            private String[] field_order_type_info = new String[]{'enableLiveChat','openNewAccountSubtab','openNewCaseSubtab','openNewContactSubtab','openNewLeadSubtab','openNewVFPageSubtab','pageNamesToOpen','showKnowledgeArticles'};
        }
        public class PushNotification_x {
            public String[] fieldNames;
            public String objectName;
            private String[] fieldNames_type_info = new String[]{'fieldNames',SOAP_M_URI,null,'0','-1','false'};
            private String[] objectName_type_info = new String[]{'objectName',SOAP_M_URI,null,'1','1','false'};
            private String[] apex_schema_type_info = new String[]{SOAP_M_URI,'true','false'};
            private String[] field_order_type_info = new String[]{'fieldNames','objectName'};
        }
        public class TabLimitConfig_x {
            public String maxNumberOfPrimaryTabs;
            public String maxNumberOfSubTabs;
            private String[] maxNumberOfPrimaryTabs_type_info = new String[]{'maxNumberOfPrimaryTabs',SOAP_M_URI,null,'0','1','false'};
            private String[] maxNumberOfSubTabs_type_info = new String[]{'maxNumberOfSubTabs',SOAP_M_URI,null,'0','1','false'};
            private String[] apex_schema_type_info = new String[]{SOAP_M_URI,'true','false'};
            private String[] field_order_type_info = new String[]{'maxNumberOfPrimaryTabs','maxNumberOfSubTabs'};
        }
        public class AppProfileActionOverride_x {
            public String profile;
            private String[] profile_type_info = new String[]{'profile',SOAP_M_URI,null,'1','1','false'};
            private String[] apex_schema_type_info = new String[]{SOAP_M_URI,'true','false'};
            private String[] field_order_type_info = new String[]{'profile'};
        }
        public class AppPreferences_x {
            public Boolean enableCustomizeMyTabs;
            public Boolean enableKeyboardShortcuts;
            public Boolean enableListViewHover;
            public Boolean enableListViewReskin;
            public Boolean enableMultiMonitorComponents;
            public Boolean enablePinTabs;
            public Boolean enableTabHover;
            public Boolean enableTabLimits;
            public Boolean saveUserSessions;
            private String[] enableCustomizeMyTabs_type_info = new String[]{'enableCustomizeMyTabs',SOAP_M_URI,null,'1','1','false'};
            private String[] enableKeyboardShortcuts_type_info = new String[]{'enableKeyboardShortcuts',SOAP_M_URI,null,'1','1','false'};
            private String[] enableListViewHover_type_info = new String[]{'enableListViewHover',SOAP_M_URI,null,'1','1','false'};
            private String[] enableListViewReskin_type_info = new String[]{'enableListViewReskin',SOAP_M_URI,null,'1','1','false'};
            private String[] enableMultiMonitorComponents_type_info = new String[]{'enableMultiMonitorComponents',SOAP_M_URI,null,'1','1','false'};
            private String[] enablePinTabs_type_info = new String[]{'enablePinTabs',SOAP_M_URI,null,'1','1','false'};
            private String[] enableTabHover_type_info = new String[]{'enableTabHover',SOAP_M_URI,null,'1','1','false'};
            private String[] enableTabLimits_type_info = new String[]{'enableTabLimits',SOAP_M_URI,null,'1','1','false'};
            private String[] saveUserSessions_type_info = new String[]{'saveUserSessions',SOAP_M_URI,null,'1','1','false'};
            private String[] apex_schema_type_info = new String[]{SOAP_M_URI,'true','false'};
            private String[] field_order_type_info = new String[]{'enableCustomizeMyTabs','enableKeyboardShortcuts','enableListViewHover','enableListViewReskin','enableMultiMonitorComponents','enablePinTabs','enableTabHover','enableTabLimits','saveUserSessions'};
        }
        public class AppWorkspaceConfig_x {
            public WorkspaceMapping_x[] mappings;
            private String[] mappings_type_info = new String[]{'mappings',SOAP_M_URI,null,'0','-1','false'};
            private String[] apex_schema_type_info = new String[]{SOAP_M_URI,'true','false'};
            private String[] field_order_type_info = new String[]{'mappings'};
        }
        public class WorkspaceMapping_x {
            public String fieldName;
            public String tab;
            private String[] fieldName_type_info = new String[]{'fieldName',SOAP_M_URI,null,'0','1','false'};
            private String[] tab_type_info = new String[]{'tab',SOAP_M_URI,null,'1','1','false'};
            private String[] apex_schema_type_info = new String[]{SOAP_M_URI,'true','false'};
            private String[] field_order_type_info = new String[]{'fieldName','tab'};
        }
        public virtual class Metadata_x {
            public String fullName;
            private String[] fullName_type_info = new String[]{'fullName','http://soap.sforce.com/2006/04/metadata',null,'0','1','false'};
            private String[] apex_schema_type_info = new String[]{'http://soap.sforce.com/2006/04/metadata','true','false'};
            private String[] field_order_type_info = new String[]{'fullName'};
        }
        public class CallOptions_element {
            public String client;
            private String[] client_type_info = new String[]{'client','http://soap.sforce.com/2006/04/metadata',null,'1','1','false'};
            private String[] apex_schema_type_info = new String[]{'http://soap.sforce.com/2006/04/metadata','true','false'};
            private String[] field_order_type_info = new String[]{'client'};
        }
        public class DebuggingHeader_element {
            public UpdatePSAllFieldsAllObjectsQueueable.LogInfo[] categories;
            public String debugLevel;
            private String[] categories_type_info = new String[]{'categories','http://soap.sforce.com/2006/04/metadata',null,'0','-1','false'};
            private String[] debugLevel_type_info = new String[]{'debugLevel','http://soap.sforce.com/2006/04/metadata',null,'1','1','false'};
            private String[] apex_schema_type_info = new String[]{'http://soap.sforce.com/2006/04/metadata','true','false'};
            private String[] field_order_type_info = new String[]{'categories','debugLevel'};
        }
        public class ReadResult {
            public UpdatePSAllFieldsAllObjectsQueueable.Metadata_x[] records;
            private String[] records_type_info = new String[]{'records','http://soap.sforce.com/2006/04/metadata',null,'0','-1','false'};
            private String[] apex_schema_type_info = new String[]{'http://soap.sforce.com/2006/04/metadata','true','false'};
            private String[] field_order_type_info = new String[]{'records'};
        }
        public class SaveResult {
            public UpdatePSAllFieldsAllObjectsQueueable.Error[] errors;
            public String fullName;
            public Boolean success;
            private String[] errors_type_info = new String[]{'errors','http://soap.sforce.com/2006/04/metadata',null,'0','-1','false'};
            private String[] fullName_type_info = new String[]{'fullName','http://soap.sforce.com/2006/04/metadata',null,'1','1','false'};
            private String[] success_type_info = new String[]{'success','http://soap.sforce.com/2006/04/metadata',null,'1','1','false'};
            private String[] apex_schema_type_info = new String[]{'http://soap.sforce.com/2006/04/metadata','true','false'};
            private String[] field_order_type_info = new String[]{'errors','fullName','success'};
        }
        
        public class ExtendedErrorDetails {
            public String extendedErrorCode;
            private String[] extendedErrorCode_type_info = new String[]{'extendedErrorCode','http://soap.sforce.com/2006/04/metadata',null,'1','1','false'};
            private String[] apex_schema_type_info = new String[]{'http://soap.sforce.com/2006/04/metadata','true','false'};
            private String[] field_order_type_info = new String[]{'extendedErrorCode'};
        }
        public class readMetadataResponse_element {
            public UpdatePSAllFieldsAllObjectsQueueable.ReadResult result;
            private String[] result_type_info = new String[]{'result','http://soap.sforce.com/2006/04/metadata',null,'1','1','false'};
            private String[] apex_schema_type_info = new String[]{'http://soap.sforce.com/2006/04/metadata','true','false'};
            private String[] field_order_type_info = new String[]{'result'};
        }
        public class AllOrNoneHeader_element {
            public Boolean allOrNone;
            private String[] allOrNone_type_info = new String[]{'allOrNone','http://soap.sforce.com/2006/04/metadata',null,'1','1','false'};
            private String[] apex_schema_type_info = new String[]{'http://soap.sforce.com/2006/04/metadata','true','false'};
            private String[] field_order_type_info = new String[]{'allOrNone'};
        }
        public class readMetadata_element {
            public String type_x;
            public String[] fullNames;
            private String[] type_x_type_info = new String[]{'type','http://soap.sforce.com/2006/04/metadata',null,'1','1','false'};
            private String[] fullNames_type_info = new String[]{'fullNames','http://soap.sforce.com/2006/04/metadata',null,'0','-1','false'};
            private String[] apex_schema_type_info = new String[]{'http://soap.sforce.com/2006/04/metadata','true','false'};
            private String[] field_order_type_info = new String[]{'type_x','fullNames'};
        }
        
        public class updateMetadataResponse_element {
            public UpdatePSAllFieldsAllObjectsQueueable.SaveResult[] result;
            private String[] result_type_info = new String[]{'result','http://soap.sforce.com/2006/04/metadata',null,'0','-1','false'};
            private String[] apex_schema_type_info = new String[]{'http://soap.sforce.com/2006/04/metadata','true','false'};
            private String[] field_order_type_info = new String[]{'result'};
        }
        public class DebuggingInfo_element {
            public String debugLog;
            private String[] debugLog_type_info = new String[]{'debugLog','http://soap.sforce.com/2006/04/metadata',null,'1','1','false'};
            private String[] apex_schema_type_info = new String[]{'http://soap.sforce.com/2006/04/metadata','true','false'};
            private String[] field_order_type_info = new String[]{'debugLog'};
        }
        public class LogInfo {
            public String category;
            public String level;
            private String[] category_type_info = new String[]{'category','http://soap.sforce.com/2006/04/metadata',null,'1','1','false'};
            private String[] level_type_info = new String[]{'level','http://soap.sforce.com/2006/04/metadata',null,'1','1','false'};
            private String[] apex_schema_type_info = new String[]{'http://soap.sforce.com/2006/04/metadata','true','false'};
            private String[] field_order_type_info = new String[]{'category','level'};
        }
        
        public class Error {
            public UpdatePSAllFieldsAllObjectsQueueable.ExtendedErrorDetails[] extendedErrorDetails;
            public String[] fields;
            public String message;
            public String statusCode;
            private String[] extendedErrorDetails_type_info = new String[]{'extendedErrorDetails','http://soap.sforce.com/2006/04/metadata',null,'0','-1','false'};
            private String[] fields_type_info = new String[]{'fields','http://soap.sforce.com/2006/04/metadata',null,'0','-1','false'};
            private String[] message_type_info = new String[]{'message','http://soap.sforce.com/2006/04/metadata',null,'1','1','false'};
            private String[] statusCode_type_info = new String[]{'statusCode','http://soap.sforce.com/2006/04/metadata',null,'1','1','false'};
            private String[] apex_schema_type_info = new String[]{'http://soap.sforce.com/2006/04/metadata','true','false'};
            private String[] field_order_type_info = new String[]{'extendedErrorDetails','fields','message','statusCode'};
        }
        
        public class updateMetadata_element {
            public UpdatePSAllFieldsAllObjectsQueueable.Metadata_x[] metadata;
            private String[] metadata_type_info = new String[]{'metadata','http://soap.sforce.com/2006/04/metadata',null,'0','-1','false'};
            private String[] apex_schema_type_info = new String[]{'http://soap.sforce.com/2006/04/metadata','true','false'};
            private String[] field_order_type_info = new String[]{'metadata'};
        }
        public class SessionHeader_element {
            public String sessionId;
            private String[] sessionId_type_info = new String[]{'sessionId','http://soap.sforce.com/2006/04/metadata',null,'1','1','false'};
            private String[] apex_schema_type_info = new String[]{'http://soap.sforce.com/2006/04/metadata','true','false'};
            private String[] field_order_type_info = new String[]{'sessionId'};
        }
        
        
        public interface IReadResult {
            UpdatePSAllFieldsAllObjectsQueueable.Metadata_x[] getRecords();
        }
        public interface IReadResponseElement {
            IReadResult getResult();
        }
        public class ReadPermissionSetResult implements IReadResult {
            public PermissionSet_x[] records;
            public Metadata_x[] getRecords() { return records; }
            private String[] records_type_info = new String[]{'records',SOAP_M_URI,null,'0','-1','false'};
            private String[] apex_schema_type_info = new String[]{SOAP_M_URI,'true','false'};
            private String[] field_order_type_info = new String[]{'records'};
        }
        public class readPermissionSetResponse_element implements IReadResponseElement {
            public UpdatePSAllFieldsAllObjectsQueueable.ReadPermissionSetResult result;
            public IReadResult getResult() { return result; }
            private String[] result_type_info = new String[]{'result',SOAP_M_URI,null,'1','1','false'};
            private String[] apex_schema_type_info = new String[]{SOAP_M_URI,'true','false'};
            private String[] field_order_type_info = new String[]{'result'};
        }
    

        public Class MdPort{
        public String endpoint_x = URL.getOrgDomainUrl().toExternalForm() + '/services/Soap/m/62.0';
        public Map<String,String> inputHttpHeaders_x;
        public Map<String,String> outputHttpHeaders_x;
        public String clientCertName_x;
        public String clientCert_x;
        public String clientCertPasswd_x;
        public Integer timeout_x;
        public  SessionHeader_element SessionHeader;
        public UpdatePSAllFieldsAllObjectsQueueable.CallOptions_element CallOptions;
        public UpdatePSAllFieldsAllObjectsQueueable.AllOrNoneHeader_element AllOrNoneHeader;
        private String SessionHeader_hns = 'SessionHeader=http://soap.sforce.com/2006/04/metadata';
        private String CallOptions_hns = 'CallOptions=http://soap.sforce.com/2006/04/metadata';
        private String AllOrNoneHeader_hns = 'AllOrNoneHeader=http://soap.sforce.com/2006/04/metadata';
        private String[] ns_map_type_info = new String[]{'http://soap.sforce.com/2006/04/metadata', 'UpdatePSAllFieldsAllObjectsQueueable'};
        public UpdatePSAllFieldsAllObjectsQueueable.SaveResult[] updateMetadata(UpdatePSAllFieldsAllObjectsQueueable.Metadata_x[] metadata) {
            UpdatePSAllFieldsAllObjectsQueueable.updateMetadata_element request_x = new UpdatePSAllFieldsAllObjectsQueueable.updateMetadata_element();
            request_x.metadata = metadata;
            UpdatePSAllFieldsAllObjectsQueueable.updateMetadataResponse_element response_x;
            Map<String, UpdatePSAllFieldsAllObjectsQueueable.updateMetadataResponse_element> response_map_x = new Map<String, UpdatePSAllFieldsAllObjectsQueueable.updateMetadataResponse_element>();
            response_map_x.put('response_x', response_x);
            WebServiceCallout.invoke(
                this,
                request_x,
                response_map_x,
                new String[]{endpoint_x,
                '',
                SOAP_M_URI,
                'updateMetadata',
                SOAP_M_URI,
                'updateMetadataResponse',
                'UpdatePSAllFieldsAllObjectsQueueable.updateMetadataResponse_element'}
            );
            response_x = response_map_x.get('response_x');
            return response_x.result;
        }
        
        public ReadMetadataResult readMetadata(String type_x,String[] fullNames) {
            UpdatePSAllFieldsAllObjectsQueueable.readMetadata_element request_x = new UpdatePSAllFieldsAllObjectsQueueable.readMetadata_element();
            request_x.type_x = type_x;
            request_x.fullNames = fullNames;
            UpdatePSAllFieldsAllObjectsQueueable.IReadResponseElement response_x;
            Map<String, UpdatePSAllFieldsAllObjectsQueueable.IReadResponseElement> response_map_x = new Map<String, UpdatePSAllFieldsAllObjectsQueueable.IReadResponseElement>();
            response_map_x.put('response_x', response_x);
            try {
                    WebServiceCallout.invoke(
                    this,
                    request_x,
                    response_map_x,
                    new String[]{endpoint_x,
                    '',
                    SOAP_M_URI,
                    'readMetadata',
                    SOAP_M_URI,
                    'readMetadataResponse',
                    'UpdatePSAllFieldsAllObjectsQueueable.read' + type_x + 'Response_element'}
                );
                response_x = response_map_x.get('response_x');
                return new ReadMetadataResult(response_x.getResult());
            } catch (MetadataServiceException e){
                debug('Web Service Callout Error ' + e.getMessage());
                return new ReadMetadataResult(e);
            }
            
            
        }
    
        }

    public Class ReadMetadataResult {
        // This is an attempt to trap the callout and auto-retry, but it does not seem possible
        // to trap the WebServiceCallout error properly
        public UpdatePSAllFieldsAllObjectsQueueable.IReadResult result {get;set;}
        public MetadataServiceException e {get;set;}
        public Boolean IsError {get;set;}
        public ReadMetadataResult(MetadataServiceException ex){
            e = ex;
            IsError = true;
        }
        public ReadMetadataResult(UpdatePSAllFieldsAllObjectsQueueable.IReadResult res){
            result = res;
            IsError = false;
        }
    }
    
    

}
