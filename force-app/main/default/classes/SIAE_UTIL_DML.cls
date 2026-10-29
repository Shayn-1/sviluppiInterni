/**
 * @description       : 
 * @author            : Domenico Del Prete - domenico.delprete@nttdata.com
 * @group             : NTT Data
 * @last modified on  : 06-30-2026
 * @last modified by  : Domenico Del Prete - domenico.delprete@nttdata.com
**/
public with sharing class SIAE_UTIL_DML {
    
    
    /**
    * @description 
    * @author Domenico Del Prete - domenico.delprete@nttdata.com | 08-17-2025 
    * @param listToInsert 
    **/
    public static void insertRecord(sObject sObjToInsert){
        List<SObject> listToInsert = new List<SObject>{sObjToInsert};
        insertRecords(listToInsert, true);
    }

    /**
    * @description 
    * @author Domenico Del Prete - domenico.delprete@nttdata.com | 08-17-2025 
    * @param listToInsert 
    **/
    public static void insertRecords(List<sObject> listToInsert){
        insertRecords(listToInsert, true);
    }

    /**
    * @description 
    * @author Domenico Del Prete - domenico.delprete@nttdata.com | 08-17-2025 
    * @param listToInsert 
    * @param allOrNone 
    **/
    public static void insertRecords(List<sObject> listToInsert, Boolean allOrNone) {
        try {
            List<Database.SaveResult> results = Database.insert(listToInsert, allOrNone);
            logFailedResults(results, listToInsert);
        } catch (Exception ex) {
            SIAE_UTIL_Log.logException(ex, null, getFirstRecordId(listToInsert), 'SIAE_UTIL_DML');
            throw ex;
        }
    }

    /**
    * @description 
    * @author Domenico Del Prete - domenico.delprete@nttdata.com | 08-17-2025 
    * @param listToUpdate 
    **/
    public static void updateRecord(sObject sObjToUpdate){
        List<SObject> listToUpdate = new List<SObject>{sObjToUpdate};
        updateRecords(listToUpdate, true);
    }

    /**
    * @description 
    * @author Domenico Del Prete - domenico.delprete@nttdata.com | 08-17-2025 
    * @param listToUpdate 
    **/
    public static void updateRecords(List<sObject> listToUpdate){
        updateRecords(listToUpdate, true);
    }

    /**
    * @description 
    * @author Domenico Del Prete - domenico.delprete@nttdata.com | 08-17-2025 
    * @param listToUpdate 
    * @param allOrNone 
    **/
    public static void updateRecords(List<sObject> listToUpdate, Boolean allOrNone) {
        try {
            List<Database.SaveResult> results = Database.update(listToUpdate, allOrNone);
            logFailedResults(results, listToUpdate);
        } catch (Exception ex) {
            SIAE_UTIL_Log.logException(ex, null, getFirstRecordId(listToUpdate), 'SIAE_UTIL_DML');
            throw ex;
        }
    }

    /**
    * @description Logga i record falliti di una DML partial-success (allOrNone = false).
    *              In partial-success Database.insert/update non lancia eccezioni: i record
    *              non andati a buon fine vanno individuati tramite i SaveResult.
    * @param results lista dei Database.SaveResult restituiti dalla DML
    * @param records lista dei record passati alla DML (stesso ordine dei results)
    **/
    private static void logFailedResults(List<Database.SaveResult> results, List<sObject> records) {
        if (results == null) {
            return;
        }
        List<SIAE_UTIL_Log.ErrorLog> errors = new List<SIAE_UTIL_Log.ErrorLog>();
        for (Integer i = 0; i < results.size(); i++) {
            Database.SaveResult sr = results[i];
            if (!sr.isSuccess()) {
                String recordId = records != null && i < records.size() && records[i].Id != null
                    ? String.valueOf(records[i].Id)
                    : null;
                String errorMessage = '';
                for (Database.Error err : sr.getErrors()) {
                    errorMessage += err.getStatusCode() + ': ' + err.getMessage()
                        + ' [' + String.join(err.getFields(), ', ') + ']\n';
                }
                errors.add(new SIAE_UTIL_Log.ErrorLog(errorMessage, null, recordId, 'SIAE_UTIL_DML'));
            }
        }
        SIAE_UTIL_Log.logErrors(errors);
    }

    /**
    * @description Restituisce l'Id del primo record della lista, se presente.
    * @param records lista di record
    * @return Id del primo record come String, o null
    **/
    private static String getFirstRecordId(List<sObject> records) {
        return records != null && !records.isEmpty() && records[0].Id != null
            ? String.valueOf(records[0].Id)
            : null;
    }
}