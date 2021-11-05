public class RecordGenerator {
	@AuraEnabled
    public static String getRecord(Id idRecord) {
        String serialisedData = SObjectDataLoader.serialize(new Set<Id> { idRecord });
		SObjectDataLoader.RecordsBundle records = (SObjectDataLoader.RecordsBundle) 
            							JSON.deserialize(serialisedData, SObjectDataLoader.RecordsBundle.class);    
        return JSON.serialize(records.RecordSetBundles);
    }
    
    @AuraEnabled
    public static String getSobjectToApex(Id idRecord) {
        String serialisedData = SObjectDataLoader.serialize(new Set<Id> { idRecord });
		SObjectDataLoader.RecordsBundle records = (SObjectDataLoader.RecordsBundle) 
            							JSON.deserialize(serialisedData, SObjectDataLoader.RecordsBundle.class);
        
        String apexConstructor = '';
        for(SObjectDataLoader.RecordSetBundle rb: records.RecordSetBundles) {
            apexConstructor += 'insert new '+rb.ObjectType+'('+JSON.serialize(rb.Records[0]).removeEnd('}')+');\n';
        } 
         
        //removing attributes object(not used in apex constructor)
        apexConstructor = apexConstructor.replaceAll('\\{\\"attributes\\":\\{[a-zA-Z\":,\\/0-9.]*\\},', '');
        //removing Id's
        apexConstructor = apexConstructor.replaceAll('\\"Id\\":\\"[a-zA-Z0-9]*\\",?\\)?', '');
            
        return apexConstructor;
    }
}