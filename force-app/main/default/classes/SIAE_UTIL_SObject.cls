/**
 * @description       : 
 * @author            : Domenico Del Prete - domenico.delprete@nttdata.com
 * @group             : NTT Data
 * @last modified on  : 06-16-2026
 * @last modified by  : Domenico Del Prete - domenico.delprete@nttdata.com
**/
public with sharing class SIAE_UTIL_SObject {
    
    /** 
     * @description Given a list of sObject and a String field retuns the Set of values of that field
     * @param listSObjects - list of sObject
     * @param fieldName - field for which we want the set of values
     * @return Set<String> - the set of values
    **/
    public static Set<String> getSetFieldValues(List<sObject> listSObjects, String fieldName){
        Set<String> setFieldvalues = new Set<String>();
        for(sObject s : listSObjects) {
            if(s.get(fieldName) != null) {
                setFieldvalues.add((String) s.get(fieldName));
            }
        }
        return setFieldvalues;
    }
    

    /**
    * @description 
    * @author Domenico Del Prete - domenico.delprete@nttdata.com | 08-17-2025 
    * @param priorRecord 
    * @param actualRecord 
    * @return Map<String, String> 
    **/
    public static Map<String, String> compareSObjects(SObject priorRecord, SObject actualRecord) {
        Map<String, Object> priorObjFields = priorRecord.getPopulatedFieldsAsMap();
        Map<String, Object> actualObjFields = actualRecord.getPopulatedFieldsAsMap();
        Map<String, String> differences = new Map<String, String>();
        for (String field : priorObjFields.keySet()) {
            Object priorValue = priorObjFields.get(field);
            Object actualValue = actualObjFields.get(field);
            if (actualObjFields.containsKey(field)) {
                if (priorValue != actualValue) {
                    differences.put(field, 'Prior record: ' + priorValue + ', Actual Record: ' + actualValue);
                }
            } else {
                differences.put(field, 'Present in Prior record, Missing in Actual Record');
            }
        }
        for (String field : actualObjFields.keySet()) {
            if (!priorObjFields.containsKey(field)) {
                differences.put(field, 'Missing in Prior record, present in Actual Record: ' + actualObjFields.get(field));
            }
        }
        differences.remove('LastModifiedDate');
        differences.remove('SystemModstamp');
        return differences;
    }

    /** 
     * @description Given two Map<Id,sObject> and a fieldList returns a list that contains the records changed on the fieldList
     * @param fieldList 
     * @param mapOld 
     * @param mapNew 
     * @return static List<sObject> - the set of values
    **/
    public static List<sObject> getListChanged(List<String> fieldList, Map<Id,sObject> mapOld, Map<Id,sObject> mapNew){
        List<sObject> listChanged = new List<sObject>();
        for(sObject s : mapNew.values()){
            Id oId = (Id) s.get('Id');
            Boolean isChanged = false;
            if(oId != null) {
                for(String field : fieldList){
                    if(mapNew.get(oId).get(field) != mapOld.get(oId).get(field)){
                        isChanged = true;
                        break;
                    }
                }
            }
            if(isChanged){
                listChanged.add(s);
            }
        }
        return listChanged;
    }

    /** 
     * @description Given two Map<Id,sObject> and a fieldList returns a list that contains the Id of records changed on the fieldList
     * @param fieldList 
     * @param mapOld 
     * @param mapNew 
     * @return static List<Id> - the list of values
    **/
    public static List<Id> getListChangedIds(List<String> fieldList, Map<Id,sObject> mapOld, Map<Id,sObject> mapNew){
        List<Id> listChangedIds = new List<Id>();
        for(sObject s : mapNew.values()){
            Id oId = (Id)s.get('Id');
            Boolean isChanged = false;
            if(oId != null) {
                for(String field : fieldList){
                    if(mapNew.get(oId).get(field) != mapOld.get(oId).get(field)){
                        isChanged = true;
                        break;
                    }
                }
            }
            if(isChanged){
                listChangedIds.add((Id)s.get('Id'));
            }
        }
        return listChangedIds;
    }

    /**
    * @description 
    * @author Domenico Del Prete - domenico.delprete@nttdata.com | 10-08-2025 
    * @param record 
    * @param listOfField 
    * @param fieldListEmpty 
    * @return String 
    **/
    public static String checkBlankField(SObject record, List<String> listOfField, String fieldListEmpty) {
        if (record == null || listOfField == null || listOfField.isEmpty()) {
            return fieldListEmpty;
        }
        Map<String, Schema.SObjectType> schemaMap = Schema.getGlobalDescribe();
        Schema.SObjectType schemaObject = schemaMap.get(record.getSObjectType().getDescribe().getName());
        Map<String, Schema.SObjectField> fieldMap = schemaObject.getDescribe().fields.getMap();

        for (String field : listOfField) {
            Object valueField = record.get(field);
            if (valueField == null) {
                fieldListEmpty +='Campo ' + fieldMap.get(field).getDescribe().getLabel() + ' vuoto in ' + record.getSObjectType().getDescribe().getLabel() + '\n';
            }            
        }
        return fieldListEmpty;
    }
}