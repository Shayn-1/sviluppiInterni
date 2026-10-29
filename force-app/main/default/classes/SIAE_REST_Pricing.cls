/**
 * @description       : 
 * @author            : Domenico Del Prete - domenico.delprete@nttdata.com
 * @group             : NTT Data
 * @last modified on  : 07-08-2026
 * @last modified by  : Domenico Del Prete - domenico.delprete@nttdata.com
**/
@RestResource(urlMapping='/SIAE/Pricing/*')
global with sharing class SIAE_REST_Pricing {

    private static final String CATALOG_MDA = 'MDA';
    private static final String CATALOG_FIELD = 'SIAE_Catalog__c';

    // Catalogo normalizzato -> nome del record di SIAE_CS_ProductMatrix__c
    private static final Map<String, String> PRODUCT_MATRIX_BY_CATALOG = new Map<String, String>{
        CATALOG_MDA => 'MdA',
        'TTPP'      => 'TTPP'
    };

    public class RequestJSON {
        public List<SalesTransaction> SalesTransaction;
    }

    public class SalesTransaction {
        public List<SalesTransactionItem> SalesTransactionItem;
        public String PriceBooks;
    }

    public class SalesTransactionItem {
        public String Product;
        public String StartDate;
    }

    public class PostResponse {
        public Boolean success;
        public Object salesTransactionList;
        public String errorMessage;
    }

    @HttpPost
    global static void postPricing() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        PostResponse restResponse = new PostResponse();
        String jsonRequest;
        try {
            jsonRequest = req.requestBody.toString();
            String jsonFlow = executePricing(jsonRequest);
            System.debug('Test-->' +jsonFlow) ;
            String cleanedJson = removeKeyRecursive(jsonFlow, 'price_water_fall');
            restResponse.success = true;
            restResponse.salesTransactionList = JSON.deserializeUntyped(cleanedJson);
            restResponse.errorMessage = '';
            SIAE_UTIL_Log.logRequestResponse('inboundAPI', '/SIAE/Pricing/', 'POST', '', jsonRequest, JSON.serializePretty(restResponse.salesTransactionList), 200, 'SIAE_REST_Pricing');
            
        }catch (IllegalArgumentException e) {
            res.statusCode = 400;
            restResponse.success = false;
            restResponse.errorMessage = e.getMessage();
            restResponse.salesTransactionList = null;
            SIAE_UTIL_Log.logRequestResponse('inboundAPI', '/SIAE/Pricing/', 'POST', '', jsonRequest, JSON.serializePretty(restResponse.salesTransactionList), 400, 'SIAE_REST_Pricing');
        } catch (Exception e) {
            res.statusCode = 400;
            restResponse.success = false;
            restResponse.errorMessage = e.getMessage();
            restResponse.salesTransactionList = null;
            SIAE_UTIL_Log.logRequestResponse('inboundAPI', '/SIAE/Pricing/', 'POST', '', jsonRequest, JSON.serializePretty(restResponse.salesTransactionList), 400, 'SIAE_REST_Pricing');
        }

        res.addHeader('Content-Type', 'application/json');
        res.responseBody = Blob.valueOf(JSON.serialize(restResponse));
    }

    @TestVisible
    private static String removeKeyRecursive(String jsonString, String keyToRemove) {
        Object root = JSON.deserializeUntyped(jsonString);
        removeKey(root, keyToRemove);
        return JSON.serialize(root);
    }

    @TestVisible
    private static void removeKey(Object jsonOutputFlow, String keyToRemove) {
        if (jsonOutputFlow instanceof Map<String, Object>) {
            Map<String, Object> mapNode = (Map<String, Object>) jsonOutputFlow;
            if (mapNode.containsKey(keyToRemove)) {
                mapNode.remove(keyToRemove);
            }
            for (String k : new List<String>(mapNode.keySet())) {
                removeKey(mapNode.get(k), keyToRemove);
            }
        }
        else if (jsonOutputFlow instanceof List<Object>) {
            for (Object item : (List<Object>) jsonOutputFlow) {
                removeKey(item, keyToRemove);
            }
        }
    }

    /**
     * Normalizza SIAE_Catalog__c: vuoto o MDA -> MDA, TTPP -> TTPP, altro -> errore.
     */
    @TestVisible
    private static String resolveCatalog(String rawCatalog) {
        String catalog = String.isBlank(rawCatalog) ? CATALOG_MDA : rawCatalog.trim().toUpperCase();
        if (!PRODUCT_MATRIX_BY_CATALOG.containsKey(catalog)) {
            throw new IllegalArgumentException('Catalogo non supportato');
        }
        return catalog;
    }

    @TestVisible
    private static void checkPostHookResult(String postHookStatus, String postHookMessage) {
        if ('ERROR'.equals(postHookStatus)) {
            throw new IllegalArgumentException(postHookMessage);
        }
    }

    public static String executePricing(String jsonDataString) {
        String outputFlow = '';
        RequestJSON wrapperInput = new RequestJSON();
        wrapperInput = (RequestJSON) JSON.deserialize(jsonDataString, RequestJSON.class);
        if (wrapperInput.SalesTransaction == null || wrapperInput.SalesTransaction.isEmpty() || 
                wrapperInput.SalesTransaction[0].SalesTransactionItem == null || 
                wrapperInput.SalesTransaction[0].SalesTransactionItem.isEmpty()) {
                throw new IllegalArgumentException('Errore: Il JSON non contiene SalesTransactionItem validi.');
        }
        String targetProductId = wrapperInput.SalesTransaction[0].SalesTransactionItem[0].Product;
        String startDate = wrapperInput.SalesTransaction[0].SalesTransactionItem[0].StartDate;
        Map<String, Object> requestRoot = (Map<String, Object>) JSON.deserializeUntyped(jsonDataString);
        Map<String, Object> firstSalesTransaction = (Map<String, Object>) ((List<Object>) requestRoot.get('SalesTransaction'))[0];
        String catalog = resolveCatalog((String) firstSalesTransaction.get(CATALOG_FIELD));
        SIAE_CS_ProductMatrix__c config = SIAE_CS_ProductMatrix__c.getInstance(PRODUCT_MATRIX_BY_CATALOG.get(catalog));
        if (config == null) {
            throw new IllegalArgumentException('Configuration not found for product:' + targetProductId);
        }
        if (startDate == null) {
            throw new IllegalArgumentException('The StartDate field is required.');
        }
        if (String.isNotBlank(config.SIAE_DefaultPricebookId__c) && String.isBlank(wrapperInput.SalesTransaction[0].PriceBooks)) {
            Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(jsonDataString);
            List<Object> salesTransactionsList = (List<Object>) root.get('SalesTransaction');
            Map<String, Object> stList = (Map<String, Object>) salesTransactionsList[0];
            String priceBooks = (String) stList.get('PriceBooks');
            stList.put('PriceBooks', config.SIAE_DefaultPricebookId__c);
            jsonDataString = JSON.serialize(root);
        }
        Map<String, Object> inputFlow = new Map<String,Object>();
        inputFlow = new Map<String, Object>{
                    'pricingProcedureName' => config.SIAE_PricingProcedureName__c,
                    'contextMappingId'     => config.SIAE_ContextMappingId__c,
                    'jsonDataString'       => jsonDataString,
                    'contextDefinitionId'  => config.SIAE_ContextDefinitionId__c,
                    'startDate' => startDate,
                    'catalog' => catalog
                };
        Flow.Interview.SIAE_AL_PricingRequest flowPricingExecution = new Flow.Interview.SIAE_AL_PricingRequest(inputFlow);
        if (!Test.isRunningTest()) {
            flowPricingExecution.start();
            checkPostHookResult(
                (String) flowPricingExecution.getVariableValue('postHookStatus'),
                (String) flowPricingExecution.getVariableValue('postHookMessage')
            );
            outputFlow = (String) flowPricingExecution.getVariableValue('contextDetails');
        } else {
            outputFlow = '{"transaction": "123", "price_water_fall": {"valore": 10}, "lista": [{"price_water_fall": 5}]}';
        }

        System.debug('===== DEBUG:output flow =====');
        System.debug(outputFlow);
        return outputFlow;
    }
}