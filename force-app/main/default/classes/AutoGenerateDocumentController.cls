/**
** Author      :   Vishnu Das KP (Ceptes Software Pvt. Ltd.)
** Description :   This is the synchronous controller class 
to be used to Automatic Generation of document from process builder or flow 
using the invoicable method autoGenerateDocumentFromTemplate
**/

global with sharing class AutoGenerateDocumentController {
    private static final String BODY = 'Body';
    private static final String PAGE_BREAK = 'Page Break';
    private static final String BLANK_PAGE = 'Blank Page';
    private static final String RELATED_RECORDS = 'Related Records';
    private static final String TABLE_PLACEHOLDER = '[TABLE_PLACEHOLDER]';
    private static final String PICKLIST = 'Picklist';
    private static Map<String, String> placeHolderValueMap = new Map<String, String>();
    private static Map<Id, Sobject> idSobjectValueMap = new Map<Id, Sobject>();
    private static Map<String, Domain.QueryJsonWrapper> sectionKeyQueryJSONObjMap = new Map<String, Domain.QueryJsonWrapper>();
    private static Map<String, String> sectionKeyRecordIdTableMarkupMap = new Map<String, String>();
    private static Map<String, List<sObject>> sectionIdRecordListMap = new Map<String, List<sObject>>();
    private static Map<String, List<Domain.FieldNamesWrapper>> sectionIdFieldNamesListMap = new Map<String, List<Domain.FieldNamesWrapper>>();
    private static Map<String, Domain.RelationshipWrapper> relationshipNameInfoMap = new Map<String, Domain.RelationshipWrapper>();
    private static Map<String, Set<String>> sectionKeyRelationshipNameSetMap = new Map<String, Set<String>>();
    //set contains all user Input relateRecordIds
    private static Set<Id> relatedRecordIdSet = new Set<Id>();
    private static Set<String> referenceFieldSet = new Set<String>();
    private static Document_Template__c selectedTemplate = new Document_Template__c();
    private static List<Domain.SectionWrapper> sectionWrapperList = new List<Domain.SectionWrapper>();
    private static String objectName;
    private static String templateName = Null;
    private static String fieldValueFromRelatedRecord = Null;
    
    /*
    * Description: Method to call from process builder or flow to create document and attach it as file
    */
    @InvocableMethod(label='Generate Document' description='Generate Document via DocuPad Application corresponding to the specified Template Name.' category='DocuPad')
    global static void autoGenerateDocumentFromTemplate(List<AutoGenerateDocumentWrapper> datafromPb) { 
        //set contains all user Input wrapperObjects Before filter
        List<Domain.UserInputsDataWrapper> userInputDataWrapperList = new List<Domain.UserInputsDataWrapper>();
        List<Domain.CorporateDocumentPDFAttachmentWrapper> cropDocPDFAttachmentWrapperObjList = 
            new List<Domain.CorporateDocumentPDFAttachmentWrapper>();
        List<Domain.WebhookCalloutWrapper> eSignCalloutWrapperList = new List<Domain.WebhookCalloutWrapper>();
        Boolean sendDocumentForEsign = false;

        for(AutoGenerateDocumentWrapper userInputData : datafromPb) {
            Domain.UserInputsDataWrapper userInputDataWrapper = new Domain.UserInputsDataWrapper();
            //adding all the UserI Input-related record Id in to a set relatedRecordIdSet
            relatedRecordIdSet.add(userInputData.recordId); 
            if(templateName == Null) {
                templateName = userInputData.templateName;
            }
            if(userInputData.sendForEsign) {
                sendDocumentForEsign = userInputData.sendForEsign;
            }
            userInputDataWrapper.relatedRecordId = userInputData.recordId;
            userInputDataWrapper.templateName = userInputData.templateName;
            userInputDataWrapper.attachDocument = userInputData.attachDocument;
            userInputDataWrapper.sendForEsign = userInputData.sendForEsign;
            userInputDataWrapperList.add(userInputDataWrapper);
        }
        
        if(!relatedRecordIdSet.isEmpty()) {
            Id parentRecordId = (new list<Id>(relatedRecordIdSet)[0]);
            objectName = parentRecordId.getSObjectType().getDescribe().getName();
        }
        //Collecting template, section and fields info.
        collectTemplateInfo();
        if(!sectionIdRecordListMap.isEmpty() && !sectionIdFieldNamesListMap.isEmpty()) {
            getRelationshipFieldsInfo();
            generateTableMarkup();
        }

        //ABDS:s:20211209:Check if there is no column specified
        if (referenceFieldSet.isEmpty())
        {
            referenceFieldSet.add('Name');
        }
        //ABDS:e:20211209:

        if(!relatedRecordIdSet.isEmpty() && String.isNotBlank(objectName)) {
            String soql = 'SELECT ' + 
                String.join(new List<String>(referenceFieldSet), ',') +
                ' FROM '+ String.escapeSingleQuotes(objectName) + 
                ' WHERE Id IN :relatedRecordIdSet WITH SECURITY_ENFORCED';
            system.debug('SOQL ====>'+soql);
            List<Sobject> dynamicObject = Database.query(soql);
            for(Sobject sobj : dynamicObject) {
                idSobjectValueMap.put(sobj.Id, sobj);
            }
        }
        
        List<Corporate_Document__c> insertedCorporateDocumentList = createCorporateDocument(userInputDataWrapperList);
        System.debug('insertedCorporateDocumentList.before==>'+insertedCorporateDocumentList);
        Boolean noError = createDocumentContent(insertedCorporateDocumentList);
        System.debug('insertedCorporateDocumentList.after==>'+insertedCorporateDocumentList[0].ID);
        
        // creating CorporateDocumentPDFAttachmentWrapper object and adding in to list
        for(Integer i = 0; i < insertedCorporateDocumentList.size(); i++) {
            Domain.UserInputsDataWrapper userInputObj = userInputDataWrapperList[i];
            Corporate_Document__c cropdoc = insertedCorporateDocumentList[i];
            Domain.CorporateDocumentPDFAttachmentWrapper cropDocPDFAttachmentWrappObj = new Domain.CorporateDocumentPDFAttachmentWrapper();
            cropDocPDFAttachmentWrappObj.relatedRecordId = cropdoc.Related_Record__c;
            cropDocPDFAttachmentWrappObj.corporateDocumenId = cropdoc.Id;
            cropDocPDFAttachmentWrappObj.corporateDocumentName = cropdoc.Name;
            cropDocPDFAttachmentWrappObj.attachDocument = userInputObj.attachDocument;
            cropDocPDFAttachmentWrappObj.sendForEsign = userInputObj.sendForEsign;
            If(cropDocPDFAttachmentWrappObj.attachDocument == true || cropDocPDFAttachmentWrappObj.sendForEsign == true) {
                cropDocPDFAttachmentWrapperObjList.add(cropDocPDFAttachmentWrappObj);
            }
        }

        // creating EsignCalloutWrapper wrapper with reference field(Email and Approver Name) value
        if(sendDocumentForEsign) {
            for(Domain.UserInputsDataWrapper inputDataWrapper : userInputDataWrapperList) {
                Domain.WebhookCalloutWrapper webhookCalloutWrapper = new Domain.WebhookCalloutWrapper();
                webhookCalloutWrapper.serviceName = 'Zoho Esign';
                if(selectedTemplate.Additional_Info__c != Null) {
                    Map<String, Object> additionalInfoMap = (Map<String, Object>) JSON.deserializeUntyped(selectedTemplate.Additional_Info__c);
                    String approverNameFieldName = (String) additionalInfoMap.get('approverNameRef');
                    approverNameFieldName = approverNameFieldName.remove(objectName + '.');
                    String approverEmailFieldName = (String) additionalInfoMap.get('approverEmailRef');
                    approverEmailFieldName = approverEmailFieldName.remove(objectName + '.');
                    Sobject relatedSObject = idSobjectValueMap.get(inputDataWrapper.relatedRecordId);
                    webhookCalloutWrapper.approverName = String.valueof(relatedSObject.get(approverNameFieldName));
                    webhookCalloutWrapper.approverEmail = String.valueof(relatedSObject.get(approverEmailFieldName));
                }
                webhookCalloutWrapper.relatedRecordId = inputDataWrapper.relatedRecordId;
                webhookCalloutWrapper.templateName = inputDataWrapper.templateName; 
                eSignCalloutWrapperList.add(webhookCalloutWrapper);
            }
        }
        if(!cropDocPDFAttachmentWrapperObjList.isEmpty()) {
            PDFGeneratorQueueable pdfcontrollerObj = 
            new PDFGeneratorQueueable(cropDocPDFAttachmentWrapperObjList, eSignCalloutWrapperList, sendDocumentForEsign);
            System.enqueueJob(pdfcontrollerObj);
        }
    }

    private static void collectTemplateInfo() {
        List<Document_Template__c> templateList = new List<Document_Template__c>();
        templateList = [SELECT Id, Name, Template_Type__c, Template_Version__c, 
                        Is_Active__c, Additional_Info__c, Department__c, Description__c, 
                        Allow_Attach_As_PDF__c, Allow_Send_As_Email_Attachment__c,
                            (SELECT Id, Name, Order_Sequence__c, Content_Type__c, 
                            Visibility__c, Alignment__c, Section_Content__c, Enable_Landscape_Layout__c
                            FROM TempContents__r 
                            ORDER BY Order_Sequence__c 
                            ASC NULLS LAST)
                        FROM Document_Template__c 
                        WHERE Name = :templateName WITH SECURITY_ENFORCED]; 

        System.debug('templateList'+templateList.size());

        if(!templateList.isEmpty()) {
            selectedTemplate = templateList[0];
            if( selectedTemplate.Additional_Info__c != Null) {
                Map<String, Object> additionalInfoMap = (Map<String, Object>) JSON.deserializeUntyped(selectedTemplate.Additional_Info__c);
                if(String.isNotBlank((String) additionalInfoMap.get('approverNameRef'))) {
                    referenceFieldSet.add((String) additionalInfoMap.get('approverNameRef'));
                }
                if(String.isNotBlank((String) additionalInfoMap.get('approverEmailRef'))) {
                    referenceFieldSet.add((String) additionalInfoMap.get('approverEmailRef'));
                }
            }
            
            sectionWrapperList = FormHandler.getFormContentList(selectedTemplate.Id);
            for(Domain.SectionWrapper section : sectionWrapperList) {
                if(section.isRelatedRecords) {
                    
                    System.debug('section==>'+ section);
                    sectionIdRecordListMap.put(section.key, QueryController.getRecordList(relatedRecordIdSet, section.queryJSON));
                    Domain.QueryJsonWrapper queryJsonObj = (Domain.QueryJsonWrapper)JSON.deserialize(
                        section.queryJSON, Domain.QueryJsonWrapper.class);
                    sectionKeyQueryJSONObjMap.put(section.key, queryJsonObj);

                    for(String field : queryJsonObj.fields.split(',')) {
                        List<String> splittedField = field.trim().split('\\.'); 

                        System.debug('splittedField==>'+splittedField);
                        System.debug('relationshipNameInfoMap==>'+relationshipNameInfoMap);
                        if(splittedField.size() == 2) {
                            if(relationshipNameInfoMap.get(splittedField.get(0)) != Null) {
                                relationshipNameInfoMap.get(splittedField.get(0)).inputFieldApiNames.add(splittedField.get(1));
                            } else {
                                relationshipNameInfoMap.put(splittedField.get(0), 
                                    new Domain.RelationshipWrapper(splittedField.get(0), new List<String>{splittedField.get(1)})
                                );
                            }
                            if(sectionKeyRelationshipNameSetMap.get(section.key) != Null) {
                                Set<String> relationshipNameSet = sectionKeyRelationshipNameSetMap.get(section.key);
                                relationshipNameSet.add(splittedField.get(0));
                            } else {
                                sectionKeyRelationshipNameSetMap.put(section.key, new Set<String>{splittedField.get(0)});
                            }
                        }
                        //ABDS:s:Added this to handle only without object prefix 
                        else  if(splittedField.size() == 1) {
                            if(relationshipNameInfoMap.get(splittedField.get(0)) != Null) {
                                relationshipNameInfoMap.get(splittedField.get(0)).inputFieldApiNames.add(splittedField.get(0));
                            } else {
                                relationshipNameInfoMap.put(splittedField.get(0), 
                                    new Domain.RelationshipWrapper(splittedField.get(0), new List<String>{splittedField.get(0)})
                                );
                            }
                            if(sectionKeyRelationshipNameSetMap.get(section.key) != Null) {
                                Set<String> relationshipNameSet = sectionKeyRelationshipNameSetMap.get(section.key);
                                relationshipNameSet.add(splittedField.get(0));
                            } else {
                                sectionKeyRelationshipNameSetMap.put(section.key, new Set<String>{splittedField.get(0)});
                            }
                        }
                        //ABDS:e:
                    }
                    sectionIdFieldNamesListMap.put(section.key, QueryController.getFieldLabelList(queryJsonObj.objectName, queryJsonObj.fields));
                }

                System.debug('section.fields'+section.fields);

                for(Domain.FieldWrapper field : section.fields) {
                    //String referenceField = field.referenceField;
                    if(field.referenceField != Null) {
                        if(!field.referenceField.contains('$')) {
                            referenceFieldSet.add(field.referenceField);
                        }
                        String fieldName = field.referenceField.remove(objectName + '.');
                        placeHolderValueMap.put( '['+field.placeholderContent+']', fieldName);
                    }
                }
            }
        }
    }

    private static void generateTableMarkup() {
        for(String sectionKey : sectionIdRecordListMap.keySet()) {
            Domain.QueryJsonWrapper queryJSONObj = sectionKeyQueryJSONObjMap.get(sectionKey);
            List<Domain.FieldNamesWrapper> fieldList = sectionIdFieldNamesListMap.get(sectionKey);
            if(sectionKeyRelationshipNameSetMap.get(sectionKey) != Null) {
                fieldList = getUpdatedFieldListWithRelationshipFields(sectionKey);
            }
            List<sObject> recordList = sectionIdRecordListMap.get(sectionKey);
            //Generating table header
            String tableHeaderMarkup = '<table style="'+(String.isNotBlank(queryJSONObj.tableStyle) ? queryJSONObj.tableStyle : '')+'">';
            tableHeaderMarkup += '<tr style="'+(String.isNotBlank(queryJSONObj.tableHeaderRowStyle) ? queryJSONObj.tableHeaderRowStyle : '')+'">';
            for(Domain.FieldNamesWrapper field : fieldList) {
                tableHeaderMarkup += '<th style="'+(String.isNotBlank(queryJSONObj.tableHeaderStyle) ? queryJSONObj.tableHeaderStyle : '')+'">'
                        + field.label +'</th>';
            }
            tableHeaderMarkup += '</tr>';
            for(Id parentRecordId : relatedRecordIdSet) {
                String tableMarkup = '';
                Integer count = 0;
                for(sObject record : recordList) {
                    if(record.get(queryJSONObj.parentFieldApiName) == parentRecordId) {
                        count++;
                        if(queryJSONObj.enableAlternateRowStyle && (Math.mod(count, 2) == 1)) {
                            tableMarkup = '<tr style="'+(String.isNotBlank(queryJSONObj.row2Style) ? queryJSONObj.row2Style : '')+'">';
                        } else {
                            tableMarkup += '<tr style="'+(String.isNotBlank(queryJSONObj.row1Style) ? queryJSONObj.row1Style : '')+'">';
                        }
                        for(Domain.FieldNamesWrapper field : fieldList) {
                            List<String> splittedFieldApiName = field.apiName.split('\\.');
                            if(splittedFieldApiName.size() == 1) {
                                tableMarkup += '<td style="'+(String.isNotBlank(queryJSONObj.cellStyle) ? queryJSONObj.cellStyle : '')+'">'
                                + (String.isNotBlank((String)record.get(field.apiName)) ? record.get(field.apiName) : '')
                                +'</td>';
                            } else if(splittedFieldApiName.size() == 2) {
                                String relationshipName = splittedFieldApiName.get(0);
                                String fieldName = splittedFieldApiName.get(1);
                                tableMarkup += '<td style="'+(String.isNotBlank(queryJSONObj.cellStyle) ? queryJSONObj.cellStyle : '')+'">'
                                + (String.isNotBlank((String)record.getSObject(relationshipName).get(fieldName)) ? record.getSObject(relationshipName).get(fieldName) : '')
                                +'</td>';
                            }                            
                        }
                        tableMarkup += '</tr>';
                    }
                }
                tableMarkup += '</table>';
                sectionKeyRecordIdTableMarkupMap.put(sectionKey + '-' +parentRecordId, tableHeaderMarkup + tableMarkup);
            }
        }
    }

    private static void getRelationshipFieldsInfo() {
        for(String sectionKey : sectionKeyQueryJSONObjMap.keySet()) {
            Domain.QueryJsonWrapper queryJsonObj = sectionKeyQueryJSONObjMap.get(sectionKey);
            List<sObject> recordList = sectionIdRecordListMap.get(sectionKey);
            List<String> fieldList = queryJsonObj.fields.split(',');
            System.debug('sectionKeyRelationshipNameSetMap==>'+sectionKeyRelationshipNameSetMap);
            System.debug('sectionKey==>'+sectionKey);
            Set<String> relationshipNameSet = sectionKeyRelationshipNameSetMap.get(sectionKey);
            Integer count = 0;
            for(sObject record : recordList) {
                try {
                        System.debug('relationshipNameSet==>'+relationshipNameSet);
                        for(String relationshipName : relationshipNameSet) {
                            String relationshipNameRecordId = (String) record.getSObject(relationshipName).get('Id');
                            relationshipNameInfoMap.get(relationshipName).objectPrefix = relationshipNameRecordId.substring(0,3);
                        }
                }catch(SObjectException e) {
                    //if relation doesn't exists
                    continue;
                }
                if(++count == relationshipNameSet.size()) {
                    break;
                }
            }
        }
        List<Domain.RelationshipWrapper> relationshipWrapList = 
            QueryController.getCompletedRelationshipInfoList(relationshipNameInfoMap.values());
        for(Domain.RelationshipWrapper relationshipWrap : relationshipWrapList) {
            relationshipNameInfoMap.put(relationshipWrap.relationshipName, relationshipWrap);
        }
    }

    private static List<Domain.FieldNamesWrapper> getUpdatedFieldListWithRelationshipFields(String sectionKey) {
        List<Domain.FieldNamesWrapper> updatedFieldList = new List<Domain.FieldNamesWrapper>();
        List<Domain.FieldNamesWrapper> fieldNamesList = sectionIdFieldNamesListMap.get(sectionKey);
        Domain.QueryJsonWrapper queryJsonObj = sectionKeyQueryJSONObjMap.get(sectionKey);
        for(String field : queryJsonObj.fields.split(',')) {
            List<String> splittedField = field.trim().split('\\.');
            if(splittedField.size() == 1) {
                for(Domain.FieldNamesWrapper fieldNamesWrap : fieldNamesList) {
                    if(fieldNamesWrap.apiName.equalsIgnoreCase(splittedField.get(0))) {
                        updatedFieldList.add(fieldNamesWrap);
                        break;
                    }
                }
            } else if(splittedField.size() == 2) {
                List<Domain.FieldNamesWrapper> fieldNamesWrapList = relationshipNameInfoMap.get(splittedField.get(0)).fieldsList;
                System.debug('fieldNamesWrapList==>'+fieldNamesWrapList);
                System.debug('relationshipNameInfoMap==>'+relationshipNameInfoMap);
                
                //ABDS:s:TODO:remove this 
                if(fieldNamesWrapList == null) {
                   
                    continue;
                }
                //ABDS:e:TODO:remove this 

                for(Domain.FieldNamesWrapper fieldNamesWrap : relationshipNameInfoMap.get(splittedField.get(0)).fieldsList) {
                    if(fieldNamesWrap.apiName.equalsIgnoreCase(splittedField.get(1))) {
                        updatedFieldList.add(new Domain.FieldNamesWrapper(fieldNamesWrap.label, field.trim()));
                        break;
                    }
                }
            }
        }
        return updatedFieldList;
    }

    private static List<Corporate_Document__c> createCorporateDocument(List<Domain.UserInputsDataWrapper> userInputWrapper) {
        List<Document_Content__c> documentContentListToInsert = new List<Document_Content__c>();
        List<Corporate_Document__c> corporateDocumentListToInsert = new List<Corporate_Document__c>();
        for(Domain.UserInputsDataWrapper userInput : userInputWrapper) {
            Corporate_Document__c cropDoc = new Corporate_Document__c();
            Sobject relatedObject = idSobjectValueMap.get(userInput.relatedRecordId);
            String recordName = String.valueof(relatedObject.get('Name'));
            if(recordName != Null) {
                cropDoc.Name = userInput.templateName + ' - ' + recordName;
            } else {
                cropDoc.Name = userInput.templateName; 
            }
            cropDoc.Version__c = 'V1';
            cropDoc.Document_Stage__c ='Draft';
            cropDoc.Document_Template__c = selectedTemplate.Id;
            cropDoc.Related_Record__c = String.valueOf(userInput.relatedRecordId);
            corporateDocumentListToInsert.add(cropDoc);
        }
        
        SObjectAccessDecision securityDecision = Security.stripInaccessible(AccessType.CREATABLE, corporateDocumentListToInsert);
        
        //ABDS:s:20211209:to have updated Id. issue id is not returned therefor documnent content in not attaching
        //INSERT securityDecision.getRecords();
		if ((!Schema.sObjectType.Corporate_Document__c.fields.Name.isCreateable()) && (!Schema.sObjectType.Corporate_Document__c.fields.Version__c.isCreateable()) && (!Schema.sObjectType.Corporate_Document__c.fields.Document_Stage__c.isCreateable()) && (!Schema.sObjectType.Corporate_Document__c.fields.Version__c.isCreateable()) && (!Schema.sObjectType.Corporate_Document__c.fields.Related_Record__c.isCreateable())) {
            return null;
        }
        corporateDocumentListToInsert=securityDecision.getRecords();
        INSERT corporateDocumentListToInsert;
        //ABDS:e:20211209:
        return corporateDocumentListToInsert;
    }

    private static Boolean createDocumentContent(List<Corporate_Document__c> corporateDocumentList) {
        List<Document_Content__c> documentContentListToInsert = new List<Document_Content__c>();
        for(Corporate_Document__c cropdoc : corporateDocumentList) {
            String relatedRecordId = cropdoc.Related_Record__c;
            
            System.debug('sectionWrapperList'+ sectionWrapperList);

            for(Domain.SectionWrapper sectionWrap : sectionWrapperList) {
                Document_Content__c docContent = new Document_Content__c();
                docContent.Name = sectionWrap.name;
                docContent.Section_Key__c = sectionWrap.key;
                docContent.Order_Sequence__c = sectionWrap.orderSequence;
                docContent.Content_Type__c = sectionWrap.contentType;
                if(BODY.equals(docContent.Content_Type__c) || RELATED_RECORDS.equals(docContent.Content_Type__c)) {
                    docContent.Enable_Landscape_Layout__c = sectionWrap.isLandscapeLayout;
                }
                docContent.Corporate_Document__c = cropdoc.Id;
                if(RELATED_RECORDS.equals(docContent.Content_Type__c)) {
                    String tableMarkup = sectionKeyRecordIdTableMarkupMap.get(sectionWrap.key + '-' + relatedRecordId);
                    docContent.Section_Content__c = sectionWrap.content.replace(TABLE_PLACEHOLDER, tableMarkup);
                    documentContentListToInsert.add(docContent);
                    continue;
                }
                String valueOfContentBeforeReplacingWithFieldValue = sectionWrap.content;
                if(sectionWrap.content != Null) {
                    // Replacing values from object inplace of PlaceHolder
                    docContent.Section_Content__c = sectionWrap.content;
                    for(String placeholderKeys : placeHolderValueMap.keySet()) {
                        String contentString = sectionWrap.content;
                        if(contentString.contains(placeholderKeys)) {
                            String referenceField = placeHolderValueMap.get(placeholderKeys);
                            List<String> splittedReferenceField = new List<String>();
                            splittedReferenceField = referenceField.split('\\.');
                            Integer relationshipLevel = splittedReferenceField.size() - 1;
                            Sobject relatedObject = idSobjectValueMap.get(relatedRecordId);
                            if(!referenceField.contains('$')) {
                                if(relationshipLevel == 0) {
                                    fieldValueFromRelatedRecord = String.valueof(relatedObject.get(referenceField));
                                } else if(relationshipLevel == 1) {
                                    fieldValueFromRelatedRecord = String.valueof(
                                        relatedObject.getSObject(splittedReferenceField.get(0)).get(splittedReferenceField.get(1))
                                    );
                                } else if(relationshipLevel == 2) {
                                    fieldValueFromRelatedRecord = String.valueof(
                                        relatedObject.getSObject(splittedReferenceField.get(0)).getSObject(splittedReferenceField.get(1)).get(splittedReferenceField.get(2))
                                    );
                                } else if(relationshipLevel == 3) {
                                    fieldValueFromRelatedRecord = String.valueof(
                                        relatedObject.getSObject(splittedReferenceField.get(0)).getSObject(splittedReferenceField.get(1)).getSObject(splittedReferenceField.get(2)).get(splittedReferenceField.get(3))
                                    );
                                }
                            } else if(referenceField.contains('$')) {
                                if(referenceField.contains('$User')) {
                                    fieldValueFromRelatedRecord = TransationalDataController.getUserInfo(splittedReferenceField[1]);
                                } else if(referenceField.contains('$Organization')) {
                                    fieldValueFromRelatedRecord = TransationalDataController.getOrgInfo(splittedReferenceField[1]);    
                                } else if(referenceField.contains('$Settings')) {
                                    String refFeildAfterSplitString;
                                    refFeildAfterSplitString = referenceField.substringAfterLast('.');
                                    String customsettingName = referenceField.substringBetween('$Settings.','.');
                                    fieldValueFromRelatedRecord = TransationalDataController.getCustomSettings(customsettingName, refFeildAfterSplitString);
                                } else if(referenceField.contains('$Metadata')) {
                                    if(splittedReferenceField.size() == 4) {
                                        String customMetaDataObj = splittedReferenceField[1];
                                        String label = splittedReferenceField[2];
                                        String referenceFieldCustomMetaData = splittedReferenceField[3];
                                        fieldValueFromRelatedRecord = TransationalDataController.getCustomMetaData(customMetaDataObj, label, referenceFieldCustomMetaData);
                                    }
                                }
                            }
                            if(fieldValueFromRelatedRecord != Null) {
                                if(!referenceField.contains('$') 
                                && fieldValueFromRelatedRecord.contains('00:00:00')
                                && Util.matchStringWithRegex(fieldValueFromRelatedRecord, '[0-9]{4}-[0-9]{2}-[0-9]{2} 00:00:00')) {
                                    // call getFormatedData to get formatted date 
                                    fieldValueFromRelatedRecord = getFormatedDate(fieldValueFromRelatedRecord);
                                }
                                if(fieldValueFromRelatedRecord.contains('\r\n')) {
                                    fieldValueFromRelatedRecord = fieldValueFromRelatedRecord.replaceAll('\r\n', '<br>');
                                }
                                String newContentWithValue = contentString.replace(placeholderKeys, fieldValueFromRelatedRecord);
                                contentString = newContentWithValue;
                                sectionWrap.content = newContentWithValue;
                                docContent.Section_Content__c = contentString;
                                fieldValueFromRelatedRecord = Null;
                            }
                        }
                    }
                }
                if(sectionWrap.visibility != Null) {
                    docContent.Visibility__c = sectionWrap.visibility;
                }
                if(sectionWrap.alignment != Null) {
                    docContent.Alignment__c = sectionWrap.alignment;
                }
                documentContentListToInsert.add(docContent);
                sectionWrap.content = valueOfContentBeforeReplacingWithFieldValue;
            }
        }
        SObjectAccessDecision securityDecision = Security.stripInaccessible(AccessType.CREATABLE, documentContentListToInsert);
        
        System.debug('documentContentListToInsert.before==>'+documentContentListToInsert);
        INSERT securityDecision.getRecords();
        System.debug('documentContentListToInsert.after==>'+documentContentListToInsert[0].ID);
        return true;
    }

    private static String getFormatedDate(String inputDate) {
        Date inputDateNew = Date.valueOf(inputDate);
        String [] month = new String [] 
            {'January',
            'February',
            'March', 
            'April',
            'May',
            'June',
            'July',
            'August',
            'September',
            'October',
            'November',
            'December'};
            String formattedDate = month[inputDateNew.Month() - 1] + ' ' 
            + inputDateNew.Day() 
            + getNumberSuffix(inputDateNew.Day()) 
            + ', ' + inputDateNew.year(); 
        return formattedDate;
    }
    
    private static String getNumberSuffix(Integer inputNumber) {
        if(inputNumber >= 11 && inputNumber <= 13) {
            return 'th';
        }
        Double reminder = Math.mod(inputNumber, 10);
        if(reminder == 1) {
            return 'st'; 
        } else if(reminder == 2) {
            return 'nd'; 
            
        } else if(reminder == 3) {
            return 'rd';
        } else {
            return 'th';
        }
    }
}