global inherited sharing class AutoGenarateDocumentListViewController {
    @InvocableMethod(label='Generate Multiple Document' description='Generate bulk documents from a List View corresponding to the specified Template Name.' category='DocuPad')
    global static void autoGenerateDocumentFromTemplate(List<AutoGenerateDocumentWrapperWithIdList> dataFromListviewButton) {
        List<AutoGenerateDocumentWrapper> datawrapperList = new List<AutoGenerateDocumentWrapper>();
        List<Id> recordIds = dataFromListviewButton[0].recordIds;
        String templateNameValue = dataFromListviewButton[0].templateName;
        Boolean attachDocumentValue = dataFromListviewButton[0].attachDocument;
        Boolean sendForEsignValue = dataFromListviewButton[0].sendForEsign;
        for(Id recId : recordIds) {
            AutoGenerateDocumentWrapper datawrapperObj = new AutoGenerateDocumentWrapper();
            datawrapperObj.recordId = recId;
            datawrapperObj.templateName = templateNameValue;
            datawrapperObj.attachDocument= attachDocumentValue;
            datawrapperObj.sendForEsign = sendForEsignValue;
            datawrapperList.add(datawrapperObj);
        }
       AutoGenerateDocumentController.autoGenerateDocumentFromTemplate(datawrapperList);
    }
}