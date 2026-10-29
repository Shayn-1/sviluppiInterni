/**
 * @description       : 
 * @author            : Domenico Del Prete - domenico.delprete@nttdata.com
 * @group             : NTT Data
 * @last modified on  : 02-18-2026
 * @last modified by  : Domenico Del Prete - domenico.delprete@nttdata.com
**/
public with sharing class SIAE_LWCC001_UpdateCatalog {

    /**
     * DTO for results
     */
    public class PublishResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
    }

    /**
    * @description AuraEnabled method to publish a Platform Event with the provided Catalog Id
    * @author Domenico Del Prete - domenico.delprete@nttdata.com | 02-18-2026 
    * @param catalogId String
    * @return PublishResult 
    **/
    @AuraEnabled
    public static PublishResult publishEvent(String catalogId) {
        PublishResult res = new PublishResult();
        if (String.isBlank(catalogId)) {
            res.success = false;
            res.message = 'Catalog Id is required';
            return res;
        }
        try {
            SIAE_UpdateCatalog__e evt = new SIAE_UpdateCatalog__e(
                SIAE_CatalogId__c = catalogId
            );

            Database.SaveResult sr = EventBus.publish(evt);
            if (sr != null && sr.isSuccess()) {
                res.success = true;
                res.message = 'Catalog update event published';
            }
        } catch (Exception ex) {
            res.success = false;
            res.message = 'Exception while publishing catalog update event';
        }
        return res;
    }

}