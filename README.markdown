Generic Native SObject Data Loader
==================================

**[Deploy to Salesforce](https://githubsfdeploy.herokuapp.com/app/githubdeploy/afawcett/apex-sobjectdataloader)**

Purpose
-------

Required a native Apex way to export and import records from multiple Salesforce objects, easily via JSON using only top level record Id's as input and automatically seek out and include related records. Such JSON could be emailed, stored, transmitted to another org easily. With the ability to customise the auto scan of relationships to tweak as needed.

![Screenshot](http://andrewfawcett.files.wordpress.com/2012/11/screen-shot-2012-11-19-at-18-38-44.png)

Supporting Use Cases
--------------------

- **Import/Export.** Provide Import and Export solutions directly a native application without having to use Data Loader.
- **Generic Super Clone.** Provide a super Clone button that can be applied to any object (without further coding), that not only clones the master record but any related child detail records.
- **Post Install Setup.** Populate default data / configuration as part of a Package post installation script.
- **Org 2 Org Data Transfer.** Pass data between orgs, perhaps via an attachment in an email received via an Apex Email Handler that receives an email from Apex code in anthor org?

Example Usage
------------- 

    String serialisedData =
      SObjectDataLoader.serialize(
          new Set<Id>; { 'a00d0000007kUms' });
          
    Set<Id> recordAIds =
         SObjectDataLoader.deserialize(serialisedData);

Example output 

    {
        "RecordSetBundles": [
            {
                "Records": [
                    {
                        "Id": "a00d0000007kUmsAAE",
                        "Name": "Object A Record"
                    }
                ],
                "ObjectType": "ObjectA__c"
            },
            {
                "Records": [
                    {
                        "Id": "a03d000000EHi6tAAD",
                        "Name": "Object D Record",
                    }
                ],
                "ObjectType": "ObjectD__c"
            },
            {
                "Records": [
                    {
                        "Id": "a01d0000006JdysAAC",
                        "Name": "Object B Record",
                        "ObjectA__c": "a00d0000007kUmsAAE",
                        "ObjectD__c": "a03d000000EHi6tAAD"
                    }
                ],
            "ObjectType": "ObjectB__c"
            },
            {
                "Records": [
                    {
                        "Id": "a04d00000035cFAAAY",
                        "Name": "Object E Record"
                    }
                ],
                "ObjectType": "ObjectE__c"
            },
            {
                "Records": [
                    {
                        "Id": "a02d000000723fvAAA",
                        "Name": "Object C Record",
                        "ObjectB__c": "a01d0000006JdysAAC",
                        "ObjectE__c": "a04d00000035cFAAAY"
                    }
                ],
                "ObjectType": "ObjectC__c"
            }
        ]
    }

Feature Summary
---------------

- Simple API for export and importing Salesforce records via Apex using only Id's
- Auto walking of object relationships in order to export related or child record information
- Auto dependency resolution during import when importing records from dependent objects and self references
- Configurable engine to white list or exclude relationships not required in the import
- Import Callback API to support resolution of records not in the export or alternative records during import

History
-------

- **March 2014**, Excellent contributions made by [Sonal4J](https://github.com/Sonal4J) to further enhance for self referencing use cases, such as Account object parent child.
- **November 2012**, First developed and released via blog [entry](http://andrewfawcett.wordpress.com/2012/11/19/generic-native-sobject-data-loader)

More Information
----------------

For more information on the original release of this library please see this blog [entry](http://andrewfawcett.wordpress.com/2012/11/19/generic-native-sobject-data-loader) on this library. Please feel to raise issues and make comments here or on my blog. Thanks for reading and enjoy!

