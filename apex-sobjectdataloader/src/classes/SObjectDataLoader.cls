/**
 * Copyright (c) 2012, Andrew Fawcett
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without modification, 
 *   are permitted provided that the following conditions are met:
 *
 * - Redistributions of source code must retain the above copyright notice, 
 *      this list of conditions and the following disclaimer.
 * - Redistributions in binary form must reproduce the above copyright notice, 
 *      this list of conditions and the following disclaimer in the documentation 
 *      and/or other materials provided with the distribution.
 * - Neither the name of the FinancialForce.com, inc nor the names of its contributors 
 *      may be used to endorse or promote products derived from this software without 
 *      specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND 
 *  ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES 
 *  OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL 
 *  THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, 
 *  EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 *  OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
 *  OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 *  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
**/

/**
 * Serializes and Deserializes SObject records and related child and referenced records using the Apex JSON support
 *
 *   See https://github.com/afawcett/apex-sobjectdataloader for known issues, restrictions and TODO's
 *
 **/
public with sharing class SObjectDataLoader 
{
	/**
	 * Configuration uses a Fluent method design (http://en.wikipedia.org/wiki/Fluent_interface), 
	 **/
	public class SerializeConfig
	{
		protected Set<Schema.SObjectField> followRelationships;
		protected Set<Schema.SObjectField> followChildRelationships;
		protected Set<Schema.SObjectField> omitFields;
		
		public SerializeConfig()
		{	
			followRelationships = new Set<Schema.SObjectField>();
			followChildRelationships = new Set<Schema.SObjectField>();
			omitFields = new Set<Schema.SObjectField>(); 			
		}
		
		/**
		 * Provide a field that represents the lookup relationship the serializer should follow
		 **/
		public SerializeConfig follow(Schema.SObjectField relationshipField)
		{
			followRelationships.add(relationshipField);
			return this;
		}
		
		/**
		 * Provide a field that represents a parent child relationship the serializer should follow
		 **/
		public SerializeConfig followChild(Schema.SObjectField relationshipField)
		{
			followChildRelationships.add(relationshipField);
			return this;
		}
		
		/**
		 * Provide a field that the serializer should omit from the serialized output
		 **/
		public SerializeConfig omit(Schema.SObjectField omitField)
		{
			omitFields.add(omitField);
			if(followRelationships.contains(omitField))
				followRelationships.remove(omitField);
			if(followChildRelationships.contains(omitField))
				followChildRelationships.remove(omitField);
			return this;
		}
		
		/** 
		 * Automatically configure (removes all previous configuration)
		 *  Skip known system lookup and child relationships but include the rest (direct children only) upto certain depth, 
		 *  Caller can always add or omit specific via follow or omit methods
		 **/
		public SerializeConfig auto(Schema.SObjectType sObjectType)
		{
			followRelationships = new Set<Schema.SObjectField>();
			followChildRelationships = new Set<Schema.SObjectField>();
			omitFields = new Set<Schema.SObjectField>();
			Set<Schema.SObjectType> searched = new Set<Schema.SObjectType>();
			searchRelationships(sObjectType, 0, 0, true, searched);	
			return this;	
		}
		
		/**
		 * Seek out recursively relationships
		 **/
		private void searchRelationships(Schema.SObjectType sObjectType, Integer lookupDepth, Integer childDepth, Boolean searchChildren, Set<Schema.SObjectType> searched)
		{		
			// Stop infinite recursion	
			if(searched.contains(sObjectType) || lookupDepth > 2 || childDepth > 3) // TODO: Make max depth configurable
				return;
			searched.add(sObjectType);
			Schema.DescribeSObjectResult sObjectDescribe = sObjectType.getDescribe();
						
			// Following children? (only set for descendents of the top level object)
			if(searchChildren)
			{
				List<Schema.ChildRelationship> childRelationships = sObjectDescribe.getChildRelationships();
				for(Schema.ChildRelationship childRelationship : childRelationships)
				{
					// Determine which child relationships to automatically follow
					String childRelationshipName = childRelationship.getRelationshipName();
					if(childRelationshipName==null || 
					   childRelationshipWhitelist.contains(childRelationshipName)) // Skip relationships without names and those whitelisted
						continue;
					if(childRelationshipName.endsWith('Histories')) // Skip relationships ending in Histories (TODO: consider a RegEx approach?)
						continue;
					if(!childRelationship.isCascadeDelete()) // Skip relationships for none owned records (aka only follow master-detail relationships)
						continue;
					followChild(childRelationship.getField()).
						searchRelationships(childRelationship.getChildSObject(), lookupDepth, childDepth+1, true, searched);
				}
			}
							
			// Follow lookup relationships to long as they have not previously been added as child references and are not whitelisted
			Map<String, Schema.SObjectField> sObjectFields = sObjectDescribe.fields.getMap();
			for(Schema.SObjectField sObjectField : sObjectFields.values())
				if(sObjectField.getDescribe().getType() == Schema.DisplayType.Reference) 
					if(!followChildRelationships.contains(sObjectField) && !relationshipWhitelist.contains(sObjectField.getDescribe().getName()))
						follow(sObjectField).
							searchRelationships(sObjectField.getDescribe().getReferenceTo()[0], lookupDepth+1, childDepth, false, searched);
		}

		// Standard fields that are not included when using the auto config
		private Set<String> relationshipWhitelist = 
			new Set<String>
				{ 'OwnerId',
				  'CreatedById',
				  'LastModifiedById',
				  'RecordTypeId'
				};
				
		// Standard child relationships that are not included when using the auto config
		private Set<String> childRelationshipWhitelist = 
			new Set<String> 
				{ 'Shares', 
				  'ProcessInstances', 
				  'ProcessSteps', 
				  'Tasks', 
				  'ActivityHistories', 
				  'Attachments', 
				  'FeedSubscriptionsForEntity', 
				  'Events', 
				  'Notes', 
				  'NotesAndAttachments', 
				  'OpenActivities', 
				  'Histories', 
				  'Feeds'};		
	}
	
	
	/**
	 * Serialize the given records using the default configuration (see SerializeConfig.auto)
	 **/
	public static String serialize(Set<Id> ids)
	{
		// Serialize based on no prior knowledge of the objects
		if(ids==null || ids.size()==0)
			throw new SerializerException('List of Ids cannot be null or empty.');
		return serialize(ids, new SerializeConfig().auto(new List<Id>(ids)[0].getSObjectType()));
	}
	
	/**
	 * Serialize the given records using the given configuration
	 **/
	public static String serialize(Set<Id> ids, SerializeConfig strategy)
	{			
		// Validate parameters
		if(ids==null || ids.size()==0)
			throw new SerializerException('List of Ids cannot be null or empty.');
			
		// Container to bundle record sets into 
		RecordsBundle recordsToBundle = new RecordsBundle();
		recordsToBundle.recordSetBundles = new List<RecordSetBundle>();		
		recordsToBundle.recordSetBundlesByType = new Map<String, RecordSetBundle>();
		
		// Begin recursive serialize from given records through to related records
		Schema.SObjectType sObjectType = new List<Id>(ids)[0].getSObjectType();
		serialize(ids, sObjectType, null, strategy, 0, 0, recordsToBundle);
				
		// Serialise the records bundle container		
		return JSON.serialize(recordsToBundle);		 		
	}

	/**
	 * Deserialize the given JSON record set bundle
	 **/
	public static Set<Id> deserialize(String recordsBundleAsJSON)
	{
		return deserialize(recordsBundleAsJSON, null);
	}
		
	/**
	 * Deserialize the given JSON record set bundle utilising the given callback
	 **/
	public static Set<Id> deserialize(String recordsBundleAsJSON, IDeserializeCallback callback)
	{
		// Desearialise the records bundle
		RecordsBundle recordsBundle = (RecordsBundle) 
			JSON.deserialize(recordsBundleAsJSON, SObjectDataLoader.RecordsBundle.class);
		
		// Map to track original ID's against the new SObject record instances being inserted
		Map<Id, SObject> recordsByOriginalId = new Map<Id, SObject>();
		
		// Record set bundles are already ordered in dependency order due to serialisation approach
		Map<String, Schema.SObjectType> sObjectsByType = Schema.getGlobalDescribe();
		for(RecordSetBundle recordSetBundle : recordsBundle.recordSetBundles)
		{
			// Determine lookup / relationship fields to update prior to inserting these records
			Schema.SObjectType sObjectType = sObjectsByType.get(recordSetBundle.ObjectType);
			Map<String, Schema.SObjectField> sObjectFields = sObjectType.getDescribe().fields.getMap();
			List<Schema.SObjectField> relationshipsFields = new List<Schema.SObjectField>();
			for(Schema.SObjectField sObjectField : sObjectFields.values())
				if(sObjectField.getDescribe().getType() == Schema.DisplayType.Reference) 
					relationshipsFields.add(sObjectField);
									
			// Prepare records for insert
			List<SObject> recordsToInsert = new List<SObject>();
			List<UnresolvedReferences> unresolvedReferencesByRecord = new List<UnresolvedReferences>(); 
			for(SObject orignalRecord : recordSetBundle.Records)
			{
				// Clone the deserialised SObject to remove the original Id prior to inserting it
				SObject newRecord = orignalRecord.clone();
				recordsToInsert.add(newRecord);
				// Map the new cloned record to its old Id (once inserted this can be used to obtain the new id)
				recordsByOriginalId.put(orignalRecord.Id, newRecord);
				// Update foreign key references / lookups / master-detail relationships
				if(relationshipsFields.size()>0)
				{
					Set<Schema.SObjectField> unresolvedFieldReferences = new Set<Schema.SObjectField>(); 
					for(Schema.SObjectField sObjectField : relationshipsFields)
					{							
						// Obtained original related record Id and search map over new records by old Ids
						Id oldRelatedRecordId = (Id) orignalRecord.get(sObjectField);
						SObject newRelatedRecord = recordsByOriginalId.get(oldRelatedRecordId);
						if(newRelatedRecord!=null)
							newRecord.put(sObjectField, newRelatedRecord.Id);
						else
							unresolvedFieldReferences.add(sObjectField);
					}
					// Retain a list of records with unresolved references
					if(unresolvedFieldReferences.size()>0)
					{
						UnresolvedReferences unresolvedReferences = new UnresolvedReferences();
						unresolvedReferences.Record = newRecord;
						unresolvedReferences.References = unresolvedFieldReferences;
						unresolvedReferencesByRecord.add(unresolvedReferences);
					}	
				}
			}			
			
			// Let the caller attempt to resolve any references the above could not
			if(callback!=null && unresolvedReferencesByRecord.size()>0)
				callback.unresolvedReferences(sObjectType, unresolvedReferencesByRecord);
			
			// Insert cloned deserialised records
			recordSetBundle.Records = recordsToInsert;
			insert recordSetBundle.Records;
		}
		
		// Return Id list from the first bundle set
		return new Map<Id, SObject>(recordsBundle.recordSetBundles[0].Records).keySet();
	}
			
	private static void serialize(Set<ID> ids, Schema.SObjectType sObjectType, Schema.SObjectField queryByIdField, SerializeConfig config, Integer lookupDepth, Integer childDepth, RecordsBundle recordsToBundle)
	{		
		// Config?
		if(config==null)
			throw new SerializerException('Must pass a valid SerializeConfig instance.');
		// Stop infinite recursion
		if(lookupDepth > 3 || childDepth > 3) // TODO: Make max depth configurable
			return;
			
		// Describe object and determine fields to serialize
		Schema.DescribeSObjectResult sObjectDesc = sObjectType.getDescribe();
		Map<String, Schema.SObjectField> sObjectFields = sObjectDesc.fields.getMap();
		List<Schema.SObjectField> sObjectFieldsToSerialize = listFieldsToSerialize(sObjectFields, config);
						
		// Query records to serialize
		String fieldList = null;
		for(Schema.SObjectField sObjectField : sObjectFieldsToSerialize)
			fieldList = fieldList == null ? sObjectField.getDescribe().getName() : fieldList + ',' + sObjectField.getDescribe().getName();
		String query = String.format('select {0} from {1} where {2} in :ids order by {2}', 
			new List<String> { fieldList, sObjectDesc.getName(), queryByIdField == null ? 'id' : queryByIdField.getDescribe().getName(), 'Name' });
		Map<Id, SObject> recordsToSerializeById = new Map<Id, SObject>(Database.query(query));
		if(recordsToSerializeById.size()==0)
			return;
		
		// Any lookup relationships to folow?
		Set<Schema.SObjectField> sObjectFollowRelationships = config.followRelationships.clone();
		sObjectFollowRelationships.retainAll(sObjectFields.values());
		if(sObjectFollowRelationships.size()>0)
		{				
			// Build list of ID's for each related record
			Map<Schema.DescribeFieldResult, Set<Id>> relationshipsByField = new Map<Schema.DescribeFieldResult, Set<Id>>(); 
			for(Schema.SObjectField sObjectField : sObjectFollowRelationships)
				relationShipsByField.put(sObjectField.getDescribe(), new Set<Id>() );			
			for(SObject recordToSerialize : recordsToSerializeById.values())
			{
				for(Schema.DescribeFieldResult relationshipField : relationshipsByField.keySet())
				{
					Id relatedId = (Id) recordToSerialize.get(relationshipField.getSObjectField());
					if(relatedId!=null)
						relationshipsByField.get(relationshipField).add(relatedId);
				}
			}
			// Serialise related records
			for(Schema.DescribeFieldResult relationshipField : relationshipsByField.keySet())
			{
				Set<Id> relatedRecordIds = relationshipsByField.get(relationshipField);
				if(relatedRecordIds.size()>0)
					serialize(relatedRecordIds, relationshipField.getReferenceTo()[0], null, config, lookupDepth+1, childDepth, recordsToBundle);					
			}
		}
					
		// Add records to applicable record set bundle
		RecordSetBundle recordSetBundle = recordsToBundle.recordSetBundlesByType.get(sObjectDesc.getName());
		if(recordSetBundle!=null)
		{
			recordSetBundle.Records.addAll(recordsToSerializeById.values());
		}
		else if(recordSetBundle==null)
		{
			recordSetBundle = new RecordSetBundle();
			recordSetBundle.ObjectType = sObjectDesc.getName();
			recordSetBundle.Records = recordsToSerializeById.values();
			recordsToBundle.recordSetBundles.add(recordSetBundle);
			recordsToBundle.recordSetBundlesByType.put(recordSetBundle.ObjectType, recordSetBundle);
		}
				
		// Any child relationships to follow?
		List<Schema.ChildRelationship> childRelationships = sObjectDesc.getChildRelationships();
		for(Schema.ChildRelationship childRelationship : childRelationships)
		{ 
			// Is this a child relationship we have been asked to follow?
			Schema.SObjectType childSObjectType = childRelationship.getChildSObject();
			if(config.followChildRelationships.contains(childRelationship.getField()))
				serialize(recordsToSerializeById.keySet(), childSObjectType, childRelationship.getField(), config, lookupDepth, childDepth+1, recordsToBundle);
		}
	}
	
	private static List<Schema.SObjectField> listFieldsToSerialize(Map<String, Schema.SObjectField> sObjectFields, SerializeConfig config)
	{
		// Filter fields to serialise
		List<Schema.SObjectField> serializeFields = new List<Schema.SObjectField>(); 
		List<String> fieldNames = new List<String>(sObjectFields.keySet());
		fieldNames.sort();
		for(String fieldName : fieldNames)
		{
			// Skip fields indicated in config
			Schema.SObjectField sObjectField = sObjectFields.get(fieldName);
			if(config.omitFields!=null && config.omitFields.contains(sObjectField))
				continue;
			// Skip read only fields, such as auto numbers and formula fields
			Schema.DescribeFieldResult sObjectFieldDescribe = sObjectField.getDescribe();
			if(sObjectFieldDescribe.isAutoNumber() ||
			   sObjectFieldDescribe.isCalculated())
			   continue;	
			// Skip lookup fields not in either of the follow lists
			if(sObjectFieldDescribe.getType() == Schema.DisplayType.Reference)
				if(!(config.followRelationships.contains(sObjectField) ||
				     config.followChildRelationships.contains(sObjectField)))
				   continue;
			// Serialize this field..						
			serializeFields.add(sObjectField);
		}			
		return serializeFields;	
	}
	
	/** 
	 * General exception class
	 **/
	public class SerializerException extends Exception
	{
		
	}
	
	/**
	 * Callback used during deserialization
	 **/
	public interface IDeserializeCallback
	{
		/**
		 * Used during deserialization to allow caller to attempt to resolve references not resolved but required to insert records
		 **/
		void unresolvedReferences(Schema.SObjectType sObjectType, List<UnresolvedReferences> unresolvedReferences);
	}
	
	/**
	 * Used during deserialization to allow caller to attempt to resolve references not resolved but required to insert records
	 **/
	public class UnresolvedReferences
	{
		public SObject Record;
		public Set<Schema.SObjectField> References;
	}
	
	/**
	 * Internal Apex represnetation of the serialized output for all recordsets
	 **/
	private class RecordsBundle
	{
		// Order of bundle sets is important
		public List<RecordSetBundle> RecordSetBundles;			
		// Used by serialiser to group records by type during recursion
		public transient Map<String, RecordSetBundle> RecordSetBundlesByType;
	}
	
	/**
	 * Internal Apex represnetation of the serialized output for a given recordset
	 **/
	private class RecordSetBundle
	{
		// Groups records by type
		public String ObjectType;
		public List<SObject> Records;	
	}
	
	@IsTest(seeAllData=true) // http://stackoverflow.com/questions/9164986/how-do-i-avoid-standard-price-not-defined-when-unit-testing-an-opportunitylineit 
	public static void testManuallyConfigured()
	{				
		// Save point to rollback test data
		System.Savepoint savePoint = Database.setSavepoint();
		
		// Serialise test data into JSON record set bundle via manual configuration
		String serializedData = SObjectDataLoader.serialize(createOpportunities(), 
			new SObjectDataLoader.SerializeConfig().
				followChild(OpportunityLineItem.OpportunityId). 	// Serialize any related OpportunityLineItem's (children)
					follow(OpportunityLineItem.PricebookEntryId). 	// Serialize any related PricebookEntry's
						follow(PricebookEntry.Product2Id). 			// Serialize any related Products's
						omit(OpportunityLineItem.UnitPrice)); 		// Do not serialize the UnitPrice, as TotalPrice is enough and both cannot exist together
					
		// Rollback test data
		Database.rollback(savePoint);
		
		// Recreate test data via deserialize
		Set<ID> resultIds = SObjectDataLoader.deserialize(serializedData, new ApplyStandardPricebook());
		assertResults(resultIds);
	}
	
	@IsTest(seeAllData=true) // http://stackoverflow.com/questions/9164986/how-do-i-avoid-standard-price-not-defined-when-unit-testing-an-opportunitylineit
	public static void testAutoConfigured()
	{
		// Save point to rollback test data
		System.Savepoint savePoint = Database.setSavepoint();
		
		// Serialise test data into JSON record set bundle via auto configuraiton (with some manual tweaks)
		String serializedData = SObjectDataLoader.serialize(createOpportunities(),
			new SObjectDataLoader.SerializeConfig().
				auto(Opportunity.sObjectType). 			// Automatically determine child and related object references needed (calls follow methods)
				omit(OpportunityLineItem.UnitPrice). 	// Do not serialize the UnitPrice, as TotalPrice is enough and both cannot exist together
				omit(PricebookEntry.Pricebook2Id).		// Do not serialize any Pricebook references (these will be reassoicated apone deserialization)
				omit(Opportunity.Pricebook2Id));		// Do not serialize any Pricebook references (these will be reassoicated apone deserialization)

		// Rollback test data
		Database.rollback(savePoint);
		
		// Recreate test data via deserialize
		Set<ID> resultIds = SObjectDataLoader.deserialize(serializedData, new ApplyStandardPricebook());
		assertResults(resultIds);				
	}
	
	/**
	 * Test implemetnation of IDeserializeCallback, automatically applies Standard Pricebook to new PricebookEntry's
	 **/
	private class ApplyStandardPricebook implements SObjectDataLoader.IDeserializeCallback
	{
		private Pricebook2 standardPricebook;
		
		public ApplyStandardPricebook()
		{
			standardPricebook = [select Id from Pricebook2 where IsStandard = true];				
		}
		
		public void unresolvedReferences(Schema.SObjectType sObjectType, List<SObjectDataLoader.UnresolvedReferences> unresolvedReferences)
		{
			if(sObjectType == PricebookEntry.sObjectType) // PricebookEntry object?
				for(SObjectDataLoader.UnresolvedReferences unresolvedReference : unresolvedReferences)
					if(unresolvedReference.References.contains(PricebookEntry.Pricebook2Id)) // Pricebook2Id field?
						unresolvedReference.Record.put(PricebookEntry.Pricebook2Id, standardPricebook.id); // Set Standard Pricebook
		}		
	}
	
	private static Set<ID> createOpportunities()
	{
		// Grab the Standard Pricebook (cannot create these via Apex)
		Pricebook2 pb = [select Id from Pricebook2 where IsStandard = true];	
				
		// Insert Opportunities
		List<Opportunity> opps = new List<Opportunity>();
		List<List<Product2>> productsByOpp = new List<List<Product2>>(); 		
		List<List<PricebookEntry>> pricebookEntriesByOpp = new List<List<PricebookEntry>>(); 		
		List<List<OpportunityLineItem>> oppLinesByOpp = new List<List<OpportunityLineItem>>(); 		
		for(Integer o=0; o<10; o++)
		{
			Opportunity opp = new Opportunity();
			opp.Name = 'Test Name ' + o;
			opp.StageName = 'Open';
			opp.CloseDate = System.today();
			opps.add(opp);
			List<Product2> products = new List<Product2>();
			List<PricebookEntry> pricebookEntries = new List<PricebookEntry>();
			List<OpportunityLineItem> oppLineItems = new List<OpportunityLineItem>();
			for(Integer i=0; i<o+1; i++)
			{						
				Product2 product = new Product2();
				product.Name = opp.Name + ' : Product : ' + i;
				products.add(product);
				PricebookEntry pbe = new PricebookEntry();
				pbe.UnitPrice = 10;
				pbe.IsActive = true;
				pbe.UseStandardPrice = false;
				pbe.Pricebook2Id = pb.Id;
				pricebookEntries.add(pbe);
				OpportunityLineItem oppLineItem = new OpportunityLineItem();
				oppLineItem.Quantity = 1;
				oppLineItem.TotalPrice = 10;
				oppLineItems.add(oppLineItem);
			}
			productsByOpp.add(products);
			pricebookEntriesByOpp.add(pricebookEntries);
			oppLinesByOpp.add(oppLineItems);				
		}
		// Insert Opportunities
		insert opps;
		// Insert Products
		List<Product2> allProducts = new List<Product2>(); 
		for(List<Product2> products : productsByOpp)
		{
			allProducts.addAll(products);			
		}
		insert allProducts;
		// Insert Pricebooks
		Integer oppIdx = 0;			
		List<PricebookEntry> allPricebookEntries = new List<PricebookEntry>();				
		for(List<PricebookEntry> pricebookEntries : pricebookEntriesByOpp)
		{
			List<Product2> products = productsByOpp[oppIdx++];
			Integer lineIdx = 0;
			for(PricebookEntry pricebookEntry : pricebookEntries)
			{
				pricebookEntry.Product2Id = products[lineIdx++].Id;
			}
			allPricebookEntries.addAll(pricebookEntries);
		}			
		insert allPricebookEntries;
		// Insert Opportunity Lines
		oppIdx = 0;						
		List<OpportunityLineItem> allOppLineItems = new List<OpportunityLineItem>(); 			
		for(List<OpportunityLineItem> oppLines : oppLinesByOpp)
		{
			List<PricebookEntry> pricebookEntries = pricebookEntriesByOpp[oppIdx];
			Integer lineIdx = 0;
			for(OpportunityLineItem oppLine : oppLines)
			{
				oppLine.OpportunityId = opps[oppIdx].Id;
				oppLine.PricebookEntryId = pricebookEntries[lineIdx++].Id;
			}
			allOppLineItems.addAll(oppLines);
			oppIdx++;
		}			
		insert allOppLineItems;		
		return new Map<Id, Opportunity>(opps).keySet();			
	}
	
	private static void assertResults(Set<ID> opportunityIds)
	{
		Pricebook2 standardPriceBook = [select Id from Pricebook2 where IsStandard = true];
		List<Opportunity> opportunities = 
			[select Id, Name, Amount, 
				(select id, PricebookEntry.Product2.Name, PricebookEntry.Pricebook2Id, UnitPrice 
				 from OpportunityLineItems 
				 order by PricebookEntry.Product2.Name) 
				from Opportunity 
				where Id in :opportunityIds 
				order by Name];
		System.assertEquals(10, opportunities.size());
		System.assertEquals('Test Name 0', opportunities[0].Name);
		System.assertEquals(10, opportunities[0].Amount);
		System.assertEquals('Test Name 9', opportunities[9].Name);
		System.assertEquals(100, opportunities[9].Amount);		
		System.assertEquals(1, opportunities[0].OpportunityLineItems.size());
		System.assertEquals(10, opportunities[0].OpportunityLineItems[0].UnitPrice);
		System.assertEquals('Test Name 0 : Product : 0', opportunities[0].OpportunityLineItems[0].PricebookEntry.Product2.Name);
		System.assertEquals(standardPriceBook.Id, opportunities[0].OpportunityLineItems[0].PricebookEntry.Pricebook2Id);
		System.assertEquals(10, opportunities[9].OpportunityLineItems.size());
		System.assertEquals(10, opportunities[9].OpportunityLineItems[0].UnitPrice);
		System.assertEquals('Test Name 9 : Product : 9', opportunities[9].OpportunityLineItems[9].PricebookEntry.Product2.Name);
		System.assertEquals(standardPriceBook.Id, opportunities[9].OpportunityLineItems[9].PricebookEntry.Pricebook2Id);		
	}

	/**
		--Without Whitelisting RecordTypeId, the autoconfig serialize/deserialize
			will try to insert a new RecordType object which throws:
			'System.TypeException: DML not allowed on RecordType'

		--Test uses dynamic binding to prevent compile-time errors in orgs without RecordTypes enabled
		--Currently, the test method only tests the logic if there are 2+ RecordTypes on the Account object
			otherwise, the if statement will silently ignore the rest of the testMethod.
	**/

	@isTest(seeAllData=False)
	private static void shouldNotTryToInsertRecordType(){
		List<RecordType> accountRecordTypes = [SELECT Id, DeveloperName FROM RecordType WHERE sObjectType = 'Account' AND isActive = TRUE];
		//Only run this test if there are multiple active recordtypes on Account object
		if (accountRecordTypes.size() > 0){
			List<sObject> testAccounts = new List<Account>();
			for (RecordType aRT : accountRecordTypes){
				sObject testAccount = new Account(Name = 'Test' + aRT.DeveloperName);
				
				//dynamic binding will prevent any compile time errors if RecordTypeId field doesn't exist
				testAccount.put('RecordTypeId', aRT.Id);
				testAccounts.add(testAccount);
			}
			insert testAccounts;
			Set<Id> newAccountIds = new Set<Id>();
			for (sObject myAccount : testAccounts){
				newAccountIds.add(myAccount.Id);
			}
			String serializedData = SObjectDataLoader.serialize(newAccountIds);
			Set<Id> resultIds = SObjectDataLoader.deserialize(serializedData);
			
			//dynamic soql will prevent any compile time errors if RecordTypeId field doesn't exist
			String accountsQuery = 'SELECT Id, RecordTypeId FROM Account WHERE Id IN :newAccountIds';
			testAccounts = Database.query(accountsQuery);
			Set<Id> recordTypeIdsOfNewAccounts = new Set<Id>();

			for (sObject myAccount : testAccounts){
				recordTypeIdsOfNewAccounts.add((Id) myAccount.get('RecordTypeId'));
			}
			system.assertEquals(recordTypeIdsOfNewAccounts.size(), accountRecordTypes.size());
		}
	}
}