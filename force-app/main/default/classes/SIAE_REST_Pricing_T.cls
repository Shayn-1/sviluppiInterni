/**
 * @description       : Classe di test per SIAE_REST_Pricing
 * @author            : Gaetano Iuliano
 * @last modified on  : 07-06-2026
**/
@isTest
private class SIAE_REST_Pricing_T {
    
    @testSetup
    static void setupData() {
        SIAE_CS_ProductMatrix__c config = new SIAE_CS_ProductMatrix__c(
            Name = 'MdA',
            SIAE_PricingProcedureName__c = 'Test_Pricing_Procedure',
            SIAE_ContextMappingId__c = 'Test_Mapping_Id',
            SIAE_ContextDefinitionId__c = 'Test_Definition_Id'
        );
        insert config;
    }
    
    @isTest
    static void testPostPricing_Success() {
        String jsonRequest = '{"SalesTransaction": [{"SalesTransactionItem": [{"Product": "PROD-TEST-001", "StartDate": "2026-01-01"}]}]}';
        
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        
        req.requestURI = '/services/apexrest/SIAE/Pricing/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(jsonRequest);
        
        RestContext.request = req;
        RestContext.response = res;
        
        Test.startTest();
        // Rimosso il try-catch inutile: eventuali errori devono far fallire il test in modo pulito
        SIAE_REST_Pricing.postPricing();
        Test.stopTest();
        
        System.assertNotEquals(null, res.responseBody, 'Il responseBody non dovrebbe essere null.');
        
        String responseStr = res.responseBody.toString();
        
        // FIX: Usiamo deserializeUntyped per leggere l'oggetto genericamente senza far crashare il parser
        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(responseStr);
        
        System.assertEquals(true, (Boolean) responseMap.get('success'), 'La transazione dovrebbe avere successo.');
        System.assertNotEquals(null, responseMap.get('salesTransactionList'), 'La lista transazioni non deve essere null.');
    }
    
    @isTest
    static void testPostPricing_InvalidJSON_MissingItems() {
        String jsonRequest = '{"SalesTransaction": []}';
        
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        
        req.requestURI = '/services/apexrest/SIAE/Pricing/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(jsonRequest);
        
        RestContext.request = req;
        RestContext.response = res;
        
        Test.startTest();
        SIAE_REST_Pricing.postPricing();
        Test.stopTest();
        
        System.assertEquals(400, res.statusCode, 'Ci si aspetta uno status code 400 per JSON non valido.');
        
        String responseStr = res.responseBody.toString();
        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(responseStr);
        
        System.assertEquals(false, (Boolean) responseMap.get('success'), 'La transazione dovrebbe fallire.');
        String errorMsg = (String) responseMap.get('errorMessage');
        System.assert(errorMsg.contains('Il JSON non contiene SalesTransactionItem validi'), 'Il messaggio d\'errore non è quello atteso.');
    }
    

    
    @isTest
    static void testPostPricing_GenericException() {
        String jsonRequest = '{"SalesTransaction": {questo_non_e_valido}}';
        
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        
        req.requestURI = '/services/apexrest/SIAE/Pricing/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(jsonRequest);
        
        RestContext.request = req;
        RestContext.response = res;
        
        Test.startTest();
        SIAE_REST_Pricing.postPricing();
        Test.stopTest();
        
        String responseStr = res.responseBody.toString();
        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(responseStr);
        
        System.assertEquals(400, res.statusCode, 'Ci si aspetta uno status code 400 per eccezione generica.');
        System.assertEquals(false, (Boolean) responseMap.get('success'), 'Il success deve essere false in caso di eccezione.');
        String errorMsg = (String) responseMap.get('errorMessage');
        System.assertNotEquals('', errorMsg, 'Dovrebbe essere presente un messaggio d\'errore generico del parser JSON.');
    }

    private static Map<String, Object> postWithCatalog(String catalog, RestResponse res) {
        String jsonRequest = '{"SalesTransaction": [{"SIAE_Catalog__c": "' + catalog + '", '
            + '"SalesTransactionItem": [{"Product": "PROD-TEST-001", "StartDate": "2026-01-01"}]}]}';
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/SIAE/Pricing/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(jsonRequest);
        RestContext.request = req;
        RestContext.response = res;

        SIAE_REST_Pricing.postPricing();

        return (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
    }

    @isTest
    static void testResolveCatalog() {
        System.assertEquals('MDA', SIAE_REST_Pricing.resolveCatalog(null));
        System.assertEquals('MDA', SIAE_REST_Pricing.resolveCatalog(''));
        System.assertEquals('MDA', SIAE_REST_Pricing.resolveCatalog('MDA'));
        System.assertEquals('MDA', SIAE_REST_Pricing.resolveCatalog('mda'));
        System.assertEquals('TTPP', SIAE_REST_Pricing.resolveCatalog('TTPP'));
        System.assertEquals('TTPP', SIAE_REST_Pricing.resolveCatalog('ttpp'));
        System.assertEquals('TTPP', SIAE_REST_Pricing.resolveCatalog(' TTPP '));
        try {
            SIAE_REST_Pricing.resolveCatalog('XYZ');
            System.assert(false, 'Catalogo non supportato: attesa IllegalArgumentException');
        } catch (IllegalArgumentException e) {
            System.assertEquals('Catalogo non supportato', e.getMessage());
        }
    }

    @isTest
    static void testPostPricing_TtppCatalog_Success() {
        // Senza record MdA la richiesta riesce solo se viene usato il record TTPP.
        delete [SELECT Id FROM SIAE_CS_ProductMatrix__c WHERE Name = 'MdA'];
        insert new SIAE_CS_ProductMatrix__c(
            Name = 'TTPP',
            SIAE_PricingProcedureName__c = 'SIAE_PP_TTPP',
            SIAE_ContextMappingId__c = 'Test_Mapping_Id',
            SIAE_ContextDefinitionId__c = 'Test_Definition_Id'
        );
        RestResponse res = new RestResponse();

        Test.startTest();
        Map<String, Object> responseMap = postWithCatalog('ttpp', res);
        Test.stopTest();

        System.assertEquals(true, (Boolean) responseMap.get('success'), String.valueOf(responseMap.get('errorMessage')));
    }

    @isTest
    static void testPostPricing_TtppCatalog_MissingConfiguration() {
        RestResponse res = new RestResponse();

        Test.startTest();
        Map<String, Object> responseMap = postWithCatalog('TTPP', res);
        Test.stopTest();

        System.assertEquals(400, res.statusCode);
        System.assertEquals(false, (Boolean) responseMap.get('success'));
        System.assert(((String) responseMap.get('errorMessage')).startsWith('Configuration not found'));
    }

    @isTest
    static void testPostPricing_UnsupportedCatalog() {
        RestResponse res = new RestResponse();

        Test.startTest();
        Map<String, Object> responseMap = postWithCatalog('XYZ', res);
        Test.stopTest();

        System.assertEquals(400, res.statusCode);
        System.assertEquals(false, (Boolean) responseMap.get('success'));
        System.assertEquals('Catalogo non supportato', responseMap.get('errorMessage'));
    }

    @isTest
    static void testCheckPostHookResult() {
        SIAE_REST_Pricing.checkPostHookResult('SUCCESS', 'ok');
        SIAE_REST_Pricing.checkPostHookResult(null, null);
        try {
            SIAE_REST_Pricing.checkPostHookResult('ERROR', 'Attributi TTPP mancanti per line item LI1');
            System.assert(false, 'Post-hook in errore: attesa IllegalArgumentException');
        } catch (IllegalArgumentException e) {
            System.assertEquals('Attributi TTPP mancanti per line item LI1', e.getMessage());
        }
    }
    
    @isTest
    static void testRemoveKeyRecursive() {
        String mockJson = '{"transaction": "123", "price_water_fall": {"valore": 10}, "lista": [{"price_water_fall": 5, "altro_valore": "ok"}]}';
        
        Test.startTest();
        String cleanedJson = SIAE_REST_Pricing.removeKeyRecursive(mockJson, 'price_water_fall');
        Test.stopTest();
        
        System.assert(!cleanedJson.contains('price_water_fall'), 'La chiave price_water_fall dovrebbe essere stata completamente rimossa.');
        System.assert(cleanedJson.contains('transaction'), 'Le chiavi intatte non dovrebbero essere rimosse.');
        System.assert(cleanedJson.contains('altro_valore'), 'I valori negli array non devono essere alterati ad eccezione del target.');
    }
}