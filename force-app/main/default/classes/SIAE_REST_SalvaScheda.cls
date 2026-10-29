/**
 * @description Client REST outbound per API SIAE Digital - salvaScheda.
 *              Endpoint Swagger: POST /api/digital/salva-scheda
 *
 *              Versione OrderItem-first:
 *              - una scheda = un OrderItem / OrderLineItem
 *              - una chiamata REST salvaScheda per ogni OrderItem
 *
 *              Mapping principale:
 *              - tipoPeriodo da OrderItem.SIAE_TypeOfCoverage__c
 *              - dataInizio/dataFine da OrderItem.ServiceDate / OrderItem.EndDate
 *              - statoDda fisso P
 *              - statoDc da Order.SIAE_IncludeDC__c
 *              - idCrmSpazio da OrderItem.SIAE_SpaceId__c
 *              - idCrmOrganizzatore da Order.Account.SIAE_IDCRM__c
 *              - idCarrello da OrderItem.OrderId
 *              - idRiferimento da Order.SIAE_ReferenceId__c
 *              - tariffa.idTabella (top-level) da Product2.SIAE_IdTableDDAFlat__c/SIAE_IdTableDDA__c secondo OrderItem.SIAE_TypeOfFlatRate__c
 *              - costiStrumenti[].costiDda.idTabella da Product2.SIAE_IdTableDDAFlat__c/SIAE_IdTableDDA__c
 *              - costiStrumenti[].costiDc.idTabella da Product2.SIAE_IdTableDCFlat__c/SIAE_IdTableDC__c
 *                (DDA/DC dal PaymentItem.type; flat da OrderItem.SIAE_TypeOfFlatRate__c)
 *              - tariffa.dda da OrderItem.SIAE_TotalDA__c
 *              - tariffa.dc da OrderItem.SIAE_DirittiConnessi__c
 *              - tariffa.quotaAccordo da OrderItem.SIAE_TotalCommercialAgreement__c
 *              - tariffa.importoTotale da somma OrderItem.SIAE_TotalDA__c + SIAE_DirittiConnessi__c + SIAE_TotalCommercialAgreement__c
              - tariffa.vociCosto da OrderItem.SIAE_PaymentItems__c filtrando DDA/DC
              - tariffa.altriCosti da OrderItem.SIAE_PaymentItems__c filtrando QA
              - tariffa.costiStrumenti da OrderItem.SIAE_PaymentItems__c DDA/DC non aggregati, raggruppati per
                instrumentId, con un elemento costiStrumenti[] separato per DDA e uno per DC quando condividono
                lo stesso instrumentId (mai costiDda e costiDc nello stesso elemento)
                con fallback instrumentId da Custom Setting SIAE_StrumentoPriority__c quando il PaymentItem non ha strumento
 *              - accordo da OrderItem campi accordo/sconti
 *              - scheda.parametri da OrderItemAttribute + AttributeDefinition.Code + Scope SCHEDA
 *              - strumenti da OrderItemAttribute + AttributeDefinition.Code
 *              - mapping strumenti/parametri da SIAE_GenereLocaleParameter__mdt
 *              - codice locale SIAE risolto da SIAE_GenereLocale__mdt, ma NON serializzato
 *              - response.idSchedaDda/idSchedaDc esposti come Long (int64 SPORT) e salvati come testo su OrderItem.SIAE_DDACardId__c / SIAE_DCCardId__c
 *
 *              Nota metadata:
 *              - i Custom Metadata vengono letti con getAll(), non con SOQL.
 *              - per SIAE_GenereLocaleParameter__mdt si usa fallback:
 *                  genere specifico + SCHEDA/STRUMENTO + AttributeCode
 *                  altrimenti ALL + SCHEDA/STRUMENTO + AttributeCode
 * 
 */
global with sharing class SIAE_REST_SalvaScheda
        implements industriesintegrationfwk.ProcessIntegrationProviderAdvanced {

    private static final String CONFIG_NAME = 'SalvaScheda';
    private static final String LOG_SERVICE_NAME = 'SIAE_REST_SalvaScheda';

    private static final String DEFAULT_TIPO_SOTTOSCRIZIONE = 'NUOVO';
    private static final String DEFAULT_TIPO_PAGAMENTO_APPARECCHIO = 'APPARECCHIO';
    private static final String TIPO_PAGAMENTO_FLAT = 'FLAT';
    private static final String REVENUE_ITEM_TYPE_FLAT = 'FLAT';
    // Strumenti che non ricevono il DC FLAT di scheda: Jukebox, Video jukebox, Karaoke.
    private static final Set<String> STRUMENTI_SENZA_DC = new Set<String>{ '6', '7A', '11' };

    /*
     * UAT Negozi: sotto i 200 mq di area vendita le voci di costo DC devono
     * uscire come tipoPagamento Apparecchio / tipo LC (non FLAT), a parità di
     * importo già calcolato dalla regola FLAT esistente. Il mq è l'attributo
     * SIAE-ATTR-QTA (SIAE_GenereLocaleParameter G06_LOCALE_mq_aree_vendita).
     */
    private static final String PRODUCT_CODE_NEGOZI = 'SIAE-PROD-NEGOZI';
    private static final String NEGOZI_MQ_AREE_VENDITA_ATTRIBUTE_CODE = 'SIAE-ATTR-QTA';
    private static final Decimal NEGOZI_MQ_AREE_VENDITA_SOGLIA_APPARECCHIO = 200;
    private static final String NEGOZI_REVENUE_ITEM_TYPE_APPARECCHIO_OVERRIDE = 'LC';

    private static final String SCOPE_STRUMENTO = 'STRUMENTO';
    private static final String SCOPE_SCHEDA = 'SCHEDA';
    private static final String SCOPE_LOCALE = 'LOCALE';
    private static final String GENERE_ALL = 'ALL';
    private static final String DATA_TYPE_ENUMERATION = 'enumeration';
    private static final String DATA_TYPE_STRING = 'string';
    private static final String PRODUCT_CODE_AUTOMEZZI = 'SIAE-PROD-AUTOMEZZI';

    private static Map<String, List<SIAE_GenereLocaleParameter__mdt>> strumentoParameterIndexByKey;
    private static Map<String, String> genereCodeByGenereName;

    /*
     * Cache transazionali usate per evitare query e parsing ripetuti quando il
     * processo parte da Order e deve generare una request per ogni OrderItem.
     * Le cache vivono solo nella transazione Apex corrente e non persistono dati.
     */
    private static Map<Id, OrderItem> orderItemByIdCache = new Map<Id, OrderItem>();
    private static Map<Id, List<SObject>> orderItemAttributesByOrderItemIdCache = new Map<Id, List<SObject>>();
    private static Set<Id> preloadedOrderItemAttributeOrderItemIds = new Set<Id>();
    private static Map<String, SObject> attributeDefinitionByIdCache = new Map<String, SObject>();
    private static Map<Id, PricingPaymentItem.Wrapper> paymentWrapperByOrderItemIdCache = new Map<Id, PricingPaymentItem.Wrapper>();
    private static List<InstrumentPriorityRow> instrumentPriorityRowsCache;
    private static Map<String, String> instrumentIdByAttributeCodeCache = new Map<String, String>();
    private static Set<String> instrumentIdLookupLoadedAttributeCodes = new Set<String>();
    private static String orderItemAttributeValueFieldNameCache;
    private static Map<Id, Boolean> negoziSottoSogliaMqAreeVenditaCache = new Map<Id, Boolean>();


    @TestVisible
    private static Map<Id, Map<String, String>> testOrderItemAttributeValuesByCode;

    @TestVisible
    private static void setTestOrderItemAttributeValues(Id orderItemId, Map<String, String> valuesByCode) {
        if (!Test.isRunningTest() || orderItemId == null) { return; }

        if (testOrderItemAttributeValuesByCode == null) { testOrderItemAttributeValuesByCode = new Map<Id,Map<String,String>>(); }

        Map<String, String> normalizedValues = new Map<String, String>();
        if (valuesByCode != null) {
            for (String attributeCode : valuesByCode.keySet()) {
                if (String.isBlank(attributeCode)) { continue; }

                String rawValue = valuesByCode.get(attributeCode);
                if (String.isNotBlank(rawValue)) { normalizedValues.put(normalizeKey(attributeCode), rawValue.trim()); }
            }
        }

        testOrderItemAttributeValuesByCode.put(orderItemId, normalizedValues);
    }

    private static Map<String, String> getTestOrderItemAttributeValuesByCode(Id orderItemId) {
        if (!Test.isRunningTest() || orderItemId == null || testOrderItemAttributeValuesByCode == null) { return null; }

        if (!testOrderItemAttributeValuesByCode.containsKey(orderItemId)) { return null; }

        return new Map<String, String>(testOrderItemAttributeValuesByCode.get(orderItemId));
    }

    public class SalvaSchedaException extends Exception {}

    // =========================================================================
    // DRO / PROCESS INTEGRATION PROVIDER
    // =========================================================================

    global static List<industriesintegrationfwk.ApexProviderAttr> getProviderAttributes() {
        return SIAE_UTIL_IntegrationConfig.buildProviderAttributes(CONFIG_NAME);
    }

    global static industriesintegrationfwk.IntegrationCalloutResponse executeCallout(
        String requestGuid,
        String inputRecordId,
        String payload,
        Map<String, Object> attributes,
        industriesintegrationfwk.HttpBaseProvider httpProvider
    ) {
        String correlationId = UUID.randomUUID().toString();
        Id orderId;
        String configName = CONFIG_NAME;

        try {
            if (String.isBlank(inputRecordId)) { throw new IllegalArgumentException('inputRecordId is required.'); }

            Id lineItemId = (Id) inputRecordId;
            if (lineItemId.getSObjectType() != OrderItem.SObjectType) { throw new IllegalArgumentException('inputRecordId must be an OrderItem ID.'); }

            OrderItem inputOrderItem = [
                SELECT OrderId
                FROM OrderItem
                WHERE Id = :lineItemId
                LIMIT 1
            ];
            orderId = inputOrderItem.OrderId;

            configName = SIAE_UTIL_IntegrationConfig.resolveConfigName(attributes, CONFIG_NAME);

            SalvaSchedaBuildResult buildResult = buildRequestFromOrderItem(lineItemId);
            if (!buildResult.missingParameters.isEmpty()) { throw new IllegalArgumentException('Request salvaScheda non completa per OrderItem ' + String.valueOf(lineItemId) + '. Parametri mancanti: ' + String.join(buildResult.missingParameters,'; ') ); }

            SalvaSchedaCalloutResult calloutResult = postSalvaSchedaForDro(
                buildResult.request,
                configName,
                requestGuid,
                lineItemId,
                orderId,
                correlationId
            );

            OrderItem orderItemUpdate = buildOrderItemUpdateFromSalvaSchedaResponse(lineItemId, calloutResult);
            if (orderItemUpdate != null) { update orderItemUpdate; }

            return toIntegrationCalloutResponse(calloutResult);

        } catch (Exception ex) {
            safeLogException(ex, correlationId, orderId, LOG_SERVICE_NAME);

            return SIAE_UTIL_IntegrationConfig.buildCalloutResponse(
                false,
                500,
                ex.getMessage()
            );
        }
    }

    private static SalvaSchedaCalloutResult postSalvaSchedaForDro(
        SalvaSchedaRequest requestBody,
        String configName,
        String requestGuid,
        Id lineItemId,
        Id orderId,
        String correlationId
    ) {
        validateRequest(requestBody);

        String effectiveConfigName = String.isBlank(configName) ? CONFIG_NAME : configName.trim();
        String effectiveCorrelationId = String.isBlank(correlationId)
            ? UUID.randomUUID().toString()
            : correlationId;
        String endpoint = SIAE_UTIL_IntegrationConfig.getCalloutEndpoint(effectiveConfigName);
        String requestJson = JSON.serialize(requestBody, true);
        String transactionId = orderId == null
            ? String.valueOf(lineItemId)
            : String.valueOf(orderId);

        HttpRequest req = SIAE_UTIL_IntegrationConfig.buildHttpRequest(
            effectiveConfigName,
            transactionId,
            effectiveCorrelationId,
            requestJson
        );
        req.setHeader('Accept', 'application/json');

        HttpResponse res = new Http().send(req);
        Integer statusCode = res.getStatusCode();
        String responseBody = res.getBody();

        addOrWriteRequestResponseLog(
            null,
            effectiveCorrelationId,
            endpoint,
            'POST',
            orderId,
            requestJson,
            responseBody,
            statusCode
        );

        return parseResponse(res);
    }

    private static industriesintegrationfwk.IntegrationCalloutResponse toIntegrationCalloutResponse(
        SalvaSchedaCalloutResult result
    ) {
        Boolean isSuccess = result != null && result.success == true && String.isBlank(result.parseError);

        return SIAE_UTIL_IntegrationConfig.buildCalloutResponse(
            isSuccess,
            result == null || result.statusCode == null ? 500 : result.statusCode,
            isSuccess ? null : buildDroErrorMessage(result)
        );
    }

    private static String buildDroErrorMessage(SalvaSchedaCalloutResult result) {
        if (result == null) { return 'Callout salvaScheda non eseguito.'; }

        if (result.error != null) {
            String code = result.error.code;
            String message = result.error.message;

            if (String.isNotBlank(code) && String.isNotBlank(message)) { return code + ': ' + message; }
            if (String.isNotBlank(message)) { return message; }
            if (String.isNotBlank(code)) { return code; }
        }

        if (String.isNotBlank(result.parseError)) { return 'Errore parsing response salvaScheda: ' + result.parseError; }

        if (String.isNotBlank(result.rawBody)) { return 'HTTP ' + String.valueOf(result.statusCode) + ': ' + result.rawBody; }

        return 'HTTP ' + String.valueOf(result.statusCode) + ': ' + String.valueOf(result.status);
    }


    private static String firstNonBlank(String firstValue, String secondValue) {
        return String.isNotBlank(firstValue) ? firstValue : secondValue;
    }

    private static String firstNonBlank(String firstValue, String secondValue, String thirdValue) {
        if (String.isNotBlank(firstValue)) { return firstValue; }
        if (String.isNotBlank(secondValue)) { return secondValue; }
        return thirdValue;
    }

    // =========================================================================
    // PUBLIC API - ORDERITEM FIRST
    // =========================================================================

    /**
     * Costruisce una singola request partendo da un OrderItemId.
     *
     * Questo metodo resta utile per test puntuali o retry singoli. Internamente
     * usa la stessa pipeline bulk-safe usata dal metodo buildRequestsFromOrder,
     * così la logica di mapping rimane unica.
     */
    public static SalvaSchedaBuildResult buildRequestFromOrderItem(Id orderItemId) {
        if (orderItemId == null) { throw new SalvaSchedaException('Parametro obbligatorio mancante: orderItemId.'); }

        OrderItem oi = loadOrderItem(orderItemId);
        preloadReusableDataForOrderItems(new List<OrderItem>{ oi });
        return buildRequestFromLoadedOrderItem(oi);
    }

    /**
     * Esegue la build e poi invia una singola request per l’OrderItem indicato.
     *
     * Prima del callout viene mantenuto il controllo sui missingParameters, in
     * modo da non inviare verso SIAE una request incompleta.
     */
    public static SalvaSchedaCalloutResult postSalvaSchedaFromOrderItem(
        Id orderItemId,
        SalvaSchedaHeaders headers
    ) {
        SalvaSchedaBuildResult buildResult = buildRequestFromOrderItem(orderItemId);

        if (!buildResult.missingParameters.isEmpty()) { throw new SalvaSchedaException('Request salvaScheda non completa per OrderItem ' + String.valueOf(orderItemId) + '. Parametri mancanti: ' + String.join(buildResult.missingParameters,'; ') ); }

        SalvaSchedaCalloutResult calloutResult = postSalvaScheda(buildResult.request, headers);
        OrderItem orderItemUpdate = buildOrderItemUpdateFromSalvaSchedaResponse(orderItemId, calloutResult);

        if (orderItemUpdate != null) { update orderItemUpdate; }

        return calloutResult;
    }

    /**
     * Entry point bulk-safe per il DRo: parte dall’Order, legge tutti gli
     * OrderItem con una sola query e costruisce una request per ciascuna riga.
     *
     * A differenza della vecchia implementazione, non richiama più
     * buildRequestFromOrderItem dentro il ciclo e quindi non ripete la query
     * dell’OrderItem né le query sugli attributi per ogni singolo mapping.
     */
    public static List<SalvaSchedaBuildResult> buildRequestsFromOrder(Id orderId) {
        if (orderId == null) { throw new SalvaSchedaException('Parametro obbligatorio mancante: orderId.'); }

        List<OrderItem> orderItems = loadOrderItemsByOrderId(orderId);
        preloadReusableDataForOrderItems(orderItems);

        List<SalvaSchedaBuildResult> results = new List<SalvaSchedaBuildResult>();
        for (OrderItem oi : orderItems) {
            results.add(buildRequestFromLoadedOrderItem(oi));
        }
        return results;
    }

    /**
     * Entry point di invio massivo per Order.
     *
     * Le request vengono costruite una sola volta con buildRequestsFromOrder;
     * poi vengono inviate una per una perché l’endpoint SIAE salvaScheda rimane
     * una chiamata per scheda/OrderItem.
     */
    public static List<SalvaSchedaCalloutResult> postSalvaSchedeFromOrder(
        Id orderId,
        SalvaSchedaHeaders headers
    ) {
        if (orderId == null) { throw new SalvaSchedaException('Parametro obbligatorio mancante: orderId.'); }

        List<SalvaSchedaCalloutResult> results = new List<SalvaSchedaCalloutResult>();
        List<OrderItem> orderItemsToUpdate = new List<OrderItem>();
        List<DeferredRequestResponseLog> deferredLogs = new List<DeferredRequestResponseLog>();
        List<SalvaSchedaBuildResult> buildResults = buildRequestsFromOrder(orderId);

        try {
            for (SalvaSchedaBuildResult buildResult : buildResults) {
                if (!buildResult.missingParameters.isEmpty()) { throw new SalvaSchedaException('Request salvaScheda non completa. Parametri mancanti: ' + String.join(buildResult.missingParameters,'; ') ); }

                SalvaSchedaCalloutResult calloutResult = postSalvaScheda(
                    buildResult.request,
                    headers,
                    CONFIG_NAME,
                    deferredLogs
                );
                results.add(calloutResult);

                OrderItem orderItemUpdate = buildOrderItemUpdateFromSalvaSchedaResponse( buildResult.orderItemId, calloutResult );

                if (orderItemUpdate != null) { orderItemsToUpdate.add(orderItemUpdate); }
            }
        } finally {
            /*
             * Il logging pubblica Platform Event / DML. Nel flusso bulk viene
             * quindi scritto solo dopo avere terminato tutti i callout, altrimenti
             * il secondo callout può fallire con:
             * "You have uncommitted work pending".
             */
            flushRequestResponseLogs(deferredLogs);
        }

        /*
         * Importante: nel flusso da Order i DML sugli OrderItem vengono eseguiti
         * solo dopo avere completato tutti i callout. In questo modo evitiamo
         * errori Salesforce del tipo "You have uncommitted work pending" tra un
         * callout salvaScheda e il successivo.
         */
        if (!orderItemsToUpdate.isEmpty()) { update orderItemsToUpdate; }

        return results;
    }

    public static SalvaSchedaCalloutResult postSalvaScheda(
        SalvaSchedaRequest requestBody,
        SalvaSchedaHeaders headers
    ) {
        return postSalvaScheda(requestBody, headers, CONFIG_NAME);
    }

    private static SalvaSchedaCalloutResult postSalvaScheda(
        SalvaSchedaRequest requestBody,
        SalvaSchedaHeaders headers,
        String configName
    ) {
        return postSalvaScheda(requestBody, headers, configName, null);
    }

    private static SalvaSchedaCalloutResult postSalvaScheda(
        SalvaSchedaRequest requestBody,
        SalvaSchedaHeaders headers,
        String configName,
        List<DeferredRequestResponseLog> deferredLogs
    ) {
        String correlationId = UUID.randomUUID().toString();
        Id orderId = resolveOrderIdFromRequest(requestBody);

        try {
            validateRequest(requestBody);

            String effectiveConfigName = String.isBlank(configName) ? CONFIG_NAME : configName.trim();
            String endpoint = SIAE_UTIL_IntegrationConfig.getCalloutEndpoint(effectiveConfigName);
            String requestJson = JSON.serialize(requestBody, true);
            String transactionId = resolveTransactionIdFromRequest(requestBody);

            HttpRequest req = SIAE_UTIL_IntegrationConfig.buildHttpRequest(
                effectiveConfigName,
                transactionId,
                correlationId,
                requestJson
            );
            req.setHeader('Accept', 'application/json');

            Http http = new Http();
            HttpResponse res = http.send(req);
            Integer statusCode = res.getStatusCode();
            String responseBody = res.getBody();

            addOrWriteRequestResponseLog(
                deferredLogs,
                correlationId,
                endpoint,
                'POST',
                orderId,
                requestJson,
                responseBody,
                statusCode
            );

            return parseResponse(res);
        } catch (Exception ex) {
            safeLogException(ex, correlationId, orderId, LOG_SERVICE_NAME);
            throw ex;
        }
    }

    private static Id resolveOrderIdFromRequest(SalvaSchedaRequest requestBody) {
        if (
            requestBody == null ||
            requestBody.scheda == null ||
            String.isBlank(requestBody.scheda.idCarrello)
        ) {
            return null;
        }

        try {
            return (Id) requestBody.scheda.idCarrello;
        } catch (Exception ex) {
            return null;
        }
    }

    private static String resolveTransactionIdFromRequest(SalvaSchedaRequest requestBody) {
        if (
            requestBody == null ||
            requestBody.scheda == null ||
            String.isBlank(requestBody.scheda.idCarrello)
        ) {
            return null;
        }

        return requestBody.scheda.idCarrello;
    }

    // =========================================================================
    // BUILD REQUEST
    // =========================================================================

    private static SalvaSchedaBuildResult initializeBuildResult() {
        SalvaSchedaBuildResult buildResult = new SalvaSchedaBuildResult();
        buildResult.request = new SalvaSchedaRequest();
        buildResult.request.scheda = new SchedaData();
        buildResult.request.tariffa = new TariffaData();
        buildResult.request.accordo = new AccordoInfo();
        return buildResult;
    }

    private static void applyKnownSchedaDefaults(
        SalvaSchedaRequest request,
        SalvaSchedaBuildResult buildResult
    ) {
        request.scheda.tipoSottoscrizione = DEFAULT_TIPO_SOTTOSCRIZIONE;
        request.scheda.flagMostra = false;

        request.scheda.parametri = new List<Parametro>();
        request.scheda.strumenti = new List<Strumento>();

        request.tariffa.vociCosto = new List<VoceCosto>();
        request.tariffa.altriCosti = new List<VoceCosto>();
        request.tariffa.costiStrumenti = new List<CostiStrumento>();

        buildResult.assumptions.add('scheda.tipoSottoscrizione impostato provvisoriamente a NUOVO.');
        buildResult.assumptions.add('scheda.flagMostra impostato provvisoriamente a false.');
        buildResult.assumptions.add('accordo inizializzato sempre con new AccordoInfo().');
    }

    /**
     * Pipeline unica di build per un OrderItem già caricato.
     *
     * Tutti gli entry point pubblici passano da qui, così il mapping resta
     * centralizzato e si evita la duplicazione di logiche tra flusso singolo e
     * flusso bulk da Order.
     */
    private static SalvaSchedaBuildResult buildRequestFromLoadedOrderItem(OrderItem oi) {
        SalvaSchedaBuildResult buildResult = initializeBuildResult();
        buildResult.orderItemId = oi == null ? null : oi.Id;

        addOrderItemWarnings(oi, buildResult);

        applyKnownSchedaDefaults(buildResult.request, buildResult);
        applyTipoPeriodo(oi, buildResult);
        applyKnownSalesforceSchedaValues(oi, buildResult);
        applyKnownTariffaValues(oi, buildResult);

        buildResult.request.tariffa.altriCosti = buildAltriCostiFromPaymentItems(oi, buildResult);

        applyKnownAccordoValues(oi, buildResult);
        resolveGenereLocale(oi, buildResult);

        buildResult.request.scheda.parametri = buildSchedaParametriFromOrderItemAttributes(oi, buildResult);
        buildResult.request.scheda.strumenti = buildStrumentiFromOrderItemAttributes(oi, buildResult);

        buildResult.request.tariffa.costiStrumenti = buildCostiStrumentiFromPaymentItems(
            buildResult.request.scheda.strumenti,
            oi,
            buildResult
        );

        buildResult.request.tariffa.vociCosto = buildVociCostoFromCostiStrumenti(
            buildResult.request.tariffa.costiStrumenti,
            buildResult
        );

        addMissingBusinessFields(buildResult);
        return buildResult;
    }

    /**
     * Carica un singolo OrderItem usando la cache transazionale.
     *
     * Il metodo è usato solo dai flussi puntuali. Nei flussi da Order gli
     * OrderItem vengono caricati tutti insieme da loadOrderItemsByOrderId.
     */
    private static OrderItem loadOrderItem(Id orderItemId) {
        if (orderItemByIdCache.containsKey(orderItemId)) { return orderItemByIdCache.get(orderItemId); }

        OrderItem oi = [
            SELECT Id,
                   OrderId,
                   Order.Id,
                   Order.OrderNumber,
                   Order.SIAE_IncludeDC__c,
                   Order.AccountId,
                   Order.Account.SIAE_IDCRM__c,
            	   Order.SIAE_ReferenceId__c,
                   Product2Id,
                   Product2.Name,
                   Product2.ProductCode,
                   Product2.SIAE_IdTableDDA__c,
                   Product2.SIAE_IdTableDDAFlat__c,
                   Product2.SIAE_IdTableDC__c,
                   Product2.SIAE_IdTableDCFlat__c,
                   ServiceDate,
                   EndDate,
                   TotalPrice,
                   SIAE_TotalDA__c,
                   SIAE_DirittiConnessi__c,
                   SIAE_TotalCommercialAgreement__c,
                   SIAE_CommercialAgreementCode__c,
                   SIAE_PartnershipId__c,
                   SIAE_AssociationId__c,
                   SIAE_DCDiscountPercent__c,
                   SIAE_DDADiscountPercent__c,
                   SIAE_SpaceId__c,
                   SIAE_GenereName__c,
                   SIAE_TypeOfCoverage__c,
                   SIAE_TypeOfFlatRate__c,
                   SIAE_PaymentItems__c
            FROM OrderItem
            WHERE Id = :orderItemId
            LIMIT 1
        ];

        orderItemByIdCache.put(oi.Id, oi);
        return oi;
    }

    /**
     * Carica in un’unica query tutti gli OrderItem dell’Order.
     *
     * Questa è la strada principale per il DRo: si evita il pattern
     * "query OrderItem nel ciclo" e si prepara la cache per tutti i mapping
     * successivi.
     */
    private static List<OrderItem> loadOrderItemsByOrderId(Id orderId) {
        List<OrderItem> orderItems = [
            SELECT Id,
                   OrderId,
                   Order.Id,
                   Order.OrderNumber,
                   Order.SIAE_IncludeDC__c,
                   Order.AccountId,
                   Order.Account.SIAE_IDCRM__c,
            	   Order.SIAE_ReferenceId__c,
                   Product2Id,
                   Product2.Name,
                   Product2.ProductCode,
                   Product2.SIAE_IdTableDDA__c,
                   Product2.SIAE_IdTableDDAFlat__c,
                   Product2.SIAE_IdTableDC__c,
                   Product2.SIAE_IdTableDCFlat__c,
                   ServiceDate,
                   EndDate,
                   TotalPrice,
                   SIAE_TotalDA__c,
                   SIAE_DirittiConnessi__c,
                   SIAE_TotalCommercialAgreement__c,
                   SIAE_CommercialAgreementCode__c,
                   SIAE_PartnershipId__c,
                   SIAE_AssociationId__c,
                   SIAE_DCDiscountPercent__c,
                   SIAE_DDADiscountPercent__c,
                   SIAE_SpaceId__c,
                   SIAE_GenereName__c,
                   SIAE_TypeOfCoverage__c,
                   SIAE_TypeOfFlatRate__c,
                   SIAE_PaymentItems__c
            FROM OrderItem
            WHERE OrderId = :orderId
            ORDER BY CreatedDate ASC
        ];

        cacheOrderItems(orderItems);
        return orderItems;
    }

    /**
     * Salva gli OrderItem già letti nella cache transazionale.
     */
    private static void cacheOrderItems(List<OrderItem> orderItems) {
        if (orderItems == null) { return; }

        for (OrderItem oi : orderItems) {
            if (oi != null && oi.Id != null) { orderItemByIdCache.put(oi.Id,oi); }
        }
    }

    /**
     * Precarica i dati riutilizzati da più mapping:
     * - OrderItemAttribute per tutti gli OrderItem;
     * - AttributeDefinition collegate agli attributi;
     * - Custom Setting di priorità strumento;
     * - PaymentWrapper deserializzati.
     */
    private static void preloadReusableDataForOrderItems(List<OrderItem> orderItems) {
        cacheOrderItems(orderItems);

        Set<Id> orderItemIds = new Set<Id>();
        for (OrderItem oi : orderItems) {
            if (oi != null && oi.Id != null) { orderItemIds.add(oi.Id); }
        }

        String valueFieldName = resolveOrderItemAttributeValueFieldName();
        preloadOrderItemAttributes(orderItemIds, valueFieldName, null, null);
        getInstrumentPriorityRows();

        for (OrderItem oi : orderItems) {
            getPaymentWrapperFromOrderItem(oi, null, null, false);
        }
    }

    /**
     * Centralizza warning tecnici dell’OrderItem senza eseguire query.
     */
    private static void addOrderItemWarnings(OrderItem oi, SalvaSchedaBuildResult buildResult) {
        if (oi == null || buildResult == null) { return; }

        if (String.isBlank(oi.SIAE_GenereName__c)) { buildResult.warnings.add('OrderItem ' + oi.Id + ': SIAE_GenereName__c non valorizzato.'); }
        if (String.isBlank(oi.SIAE_TypeOfCoverage__c)) { buildResult.warnings.add('OrderItem ' + oi.Id + ': SIAE_TypeOfCoverage__c non valorizzato.'); }
        if (oi.ServiceDate == null) { buildResult.warnings.add('OrderItem ' + oi.Id + ': ServiceDate non valorizzata.'); }
        if (oi.EndDate == null) { buildResult.warnings.add('OrderItem ' + oi.Id + ': EndDate non valorizzata.'); }
        if (oi.Product2Id == null) { buildResult.warnings.add('OrderItem ' + oi.Id + ': Product2Id non valorizzato.'); }
        if (oi.TotalPrice == null) { buildResult.warnings.add('OrderItem ' + oi.Id + ': TotalPrice non valorizzato.'); }
        if (oi.get('SIAE_TotalDA__c') == null) { buildResult.warnings.add('OrderItem ' + oi.Id + ': SIAE_TotalDA__c non valorizzato.'); }
        if (oi.get('SIAE_DirittiConnessi__c') == null) { buildResult.warnings.add('OrderItem ' + oi.Id + ': SIAE_DirittiConnessi__c non valorizzato.'); }
        if (String.isBlank(asString(oi.get('SIAE_PaymentItems__c')))) { buildResult.warnings.add('OrderItem ' + oi.Id + ': SIAE_PaymentItems__c non valorizzato.'); }

        Object rawSpaceId = oi.get('SIAE_SpaceId__c');
        if (rawSpaceId == null || String.isBlank(String.valueOf(rawSpaceId))) { buildResult.warnings.add('OrderItem ' + oi.Id + ': SIAE_SpaceId__c non valorizzato.'); }
    }

    private static void applyTipoPeriodo(
        OrderItem oi,
        SalvaSchedaBuildResult buildResult
    ) {
        String coverage = oi == null ? null : oi.SIAE_TypeOfCoverage__c;

        if (String.isBlank(coverage)) { addMissingParameter(buildResult, 'scheda.tipoPeriodo: OrderItem.SIAE_TypeOfCoverage__c non valorizzato.'); return; }

        buildResult.request.scheda.tipoPeriodo =
            coverage.trim().equalsIgnoreCase('Annuale') ? 'ANNUALE' : 'STAGIONALE';

        buildResult.assumptions.add(
            'scheda.tipoPeriodo valorizzato da OrderItem.SIAE_TypeOfCoverage__c: ' +
            buildResult.request.scheda.tipoPeriodo
        );
    }

    /**
     * Indica se la licenza prevede diritti connessi: OrderItem.SIAE_DirittiConnessi__c
     * valorizzato e maggiore di zero. Quando false (0 o non valorizzato), scheda.statoDc,
     * tariffa.dc e tariffa.costiStrumenti[].costiDc non devono essere veicolati verso SPORT.
     */
    private static Boolean hasDirittiConnessi(OrderItem oi) {
        return oi != null && oi.SIAE_DirittiConnessi__c != null && oi.SIAE_DirittiConnessi__c > 0;
    }

    private static void applyKnownSalesforceSchedaValues(
        OrderItem oi,
        SalvaSchedaBuildResult buildResult
    ) {
        if (oi == null) { addMissingParameter(buildResult, 'scheda: impossibile valorizzare dati perché OrderItem nullo.'); return; }

        buildResult.request.scheda.statoDda = 'P';
        if (hasDirittiConnessi(oi)) {
            buildResult.request.scheda.statoDc =
            oi.Order != null && oi.Order.SIAE_IncludeDC__c == true ? 'P' : 'V';
        }
        buildResult.request.scheda.idCarrello = String.valueOf(oi.OrderId);

        Object referenceIdValue = oi.Order == null ? null : oi.get('Id');
        buildResult.request.scheda.idRiferimento = asString(referenceIdValue);

        buildResult.request.scheda.dataInizio = oi.ServiceDate;
        buildResult.request.scheda.dataFine = oi.EndDate;

        if (oi.ServiceDate == null) { addMissingParameter(buildResult,'scheda.dataInizio: OrderItem.ServiceDate non valorizzata.'); }
        if (oi.EndDate == null) { addMissingParameter(buildResult,'scheda.dataFine: OrderItem.EndDate non valorizzata.'); }

        Long idCrmSpazio = parseLongOrNull(oi.get('SIAE_SpaceId__c'));
        if (idCrmSpazio != null) { buildResult.request.scheda.idCrmSpazio = idCrmSpazio; } else { addMissingParameter(buildResult, 'scheda.idCrmSpazio: OrderItem.SIAE_SpaceId__c non valorizzato o non numerico.'); }

        Object idCrmOrganizzatoreValue =
            oi.Order == null || oi.Order.Account == null ? null : oi.Order.Account.get('SIAE_IDCRM__c');

        Long idCrmOrganizzatore = parseLongOrNull(idCrmOrganizzatoreValue);
        if (idCrmOrganizzatore != null) { buildResult.request.scheda.idCrmOrganizzatore = idCrmOrganizzatore; } else { addMissingParameter(buildResult, 'scheda.idCrmOrganizzatore: Order.Account.SIAE_IDCRM__c non valorizzato o non numerico.'); }

        buildResult.assumptions.add('scheda.statoDda valorizzato fisso a P.');
        buildResult.assumptions.add('scheda.statoDc valorizzato da Order.SIAE_IncludeDC__c (true = P, false = V) solo se OrderItem.SIAE_DirittiConnessi__c > 0; non veicolato per licenze senza diritti connessi.');
        buildResult.assumptions.add('scheda.idCarrello valorizzato con OrderItem.OrderId.');
        buildResult.assumptions.add('scheda.idRiferimento valorizzato da Order.SIAE_ReferenceId__c.');
        buildResult.assumptions.add('scheda.dataInizio/dataFine valorizzate da OrderItem.ServiceDate/EndDate.');
        buildResult.assumptions.add('scheda.idCrmSpazio valorizzato da OrderItem.SIAE_SpaceId__c.');
    }

    private static void applyKnownTariffaValues(
        OrderItem oi,
        SalvaSchedaBuildResult buildResult
    ) {
        if (buildResult == null || buildResult.request == null || buildResult.request.tariffa == null) { return; }
        if (oi == null) { addMissingParameter(buildResult, 'tariffa: impossibile valorizzare i dati tariffa perché OrderItem nullo.'); return; }

        if (oi.Product2Id != null) { buildResult.request.tariffa.idTabella = resolveDettaglioIdTabella(oi, true); } else { addMissingParameter(buildResult, 'tariffa.idTabella: OrderItem.Product2Id non valorizzato.'); }

        Decimal ddaValue = parseDecimalOrNull(asString(oi.get('SIAE_TotalDA__c')));
        Decimal quotaAccordoValue = parseDecimalOrNull(asString(oi.get('SIAE_TotalCommercialAgreement__c')));
        ddaValue = ddaValue != null ? ddaValue - 3 - quotaAccordoValue: null;
        if (ddaValue != null) { buildResult.request.tariffa.dda = ddaValue; } else {  addMissingParameter(buildResult, 'tariffa.dda: OrderItem.SIAE_TotalDA__c non valorizzato.'); }

        Boolean dirittiConnessiPrevisti = hasDirittiConnessi(oi);
        Decimal dcValue;
        if (dirittiConnessiPrevisti) {
            dcValue = parseDecimalOrNull(asString(oi.get('SIAE_DirittiConnessi__c'))) - 1;
        } else {
            dcValue = 0;
        }
        buildResult.request.tariffa.dc = dcValue;

        
        if (quotaAccordoValue != null) { buildResult.request.tariffa.quotaAccordo = quotaAccordoValue; } else { addMissingParameter(buildResult, 'tariffa.quotaAccordo: OrderItem.SIAE_TotalCommercialAgreement__c non valorizzato.'); }

        if (ddaValue != null || dirittiConnessiPrevisti || quotaAccordoValue != null) {
            Decimal importoTotaleValue =
                (ddaValue == null ? 0 : ddaValue) +
                (dcValue == null ? 0 : dcValue) +
                (quotaAccordoValue == null ? 0 : quotaAccordoValue);

            buildResult.request.tariffa.importoTotale =
                importoTotaleValue.setScale(2, RoundingMode.HALF_UP);
        } else { addMissingParameter( buildResult, 'tariffa.importoTotale: impossibile calcolare la somma perché OrderItem.SIAE_TotalDA__c, SIAE_DirittiConnessi__c e SIAE_TotalCommercialAgreement__c non sono valorizzati.'  ); }

        buildResult.assumptions.add('tariffa.idTabella valorizzato da Product2.SIAE_IdTableDDAFlat__c se OrderItem.SIAE_TypeOfFlatRate__c valorizzato, altrimenti Product2.SIAE_IdTableDDA__c.');
        buildResult.assumptions.add('tariffa.dda valorizzato da OrderItem.SIAE_TotalDA__c.');
        buildResult.assumptions.add('tariffa.dc valorizzato da OrderItem.SIAE_DirittiConnessi__c - 1 se > 0, altrimenti fisso a 0 (licenza senza diritti connessi).');
        buildResult.assumptions.add('tariffa.quotaAccordo valorizzato da OrderItem.SIAE_TotalCommercialAgreement__c.');
        buildResult.assumptions.add('tariffa.importoTotale valorizzato dalla somma OrderItem.SIAE_TotalDA__c + OrderItem.SIAE_DirittiConnessi__c + OrderItem.SIAE_TotalCommercialAgreement__c.');
    }

    private static void applyKnownAccordoValues(
        OrderItem oi,
        SalvaSchedaBuildResult buildResult
    ) {
        if (buildResult == null || buildResult.request == null) { return; }

        if (buildResult.request.accordo == null) { buildResult.request.accordo = new AccordoInfo(); }

        if (oi == null) { buildResult.warnings.add('accordo: impossibile valorizzare accordo perché OrderItem nullo.'); return; }

        AccordoInfo accordo = buildResult.request.accordo;

        accordo.codiceAccordo =
            asString(oi.get('SIAE_CommercialAgreementCode__c'));

        accordo.idCrmAccordo =
            parseDecimalOrNull(asString(oi.get('SIAE_PartnershipId__c')));

        accordo.idCrmAssociazione =
            parseDecimalOrNull(asString(oi.get('SIAE_AssociationId__c')));

        buildResult.assumptions.add('accordo.codiceAccordo valorizzato da OrderItem.SIAE_CommercialAgreementCode__c.');
        buildResult.assumptions.add('accordo.idCrmAccordo valorizzato da OrderItem.SIAE_PartnershipId__c.');
        buildResult.assumptions.add('accordo.idCrmAssociazione valorizzato da OrderItem.SIAE_AssociationId__c.');

        Boolean hasAccordo = String.isNotBlank(accordo.codiceAccordo) || accordo.idCrmAccordo != null;

        if (!hasAccordo) {
            buildResult.request.accordo = null;
            buildResult.assumptions.add('accordo rimosso interamente dalla request: nessun accordo presente sull\'OrderItem (codiceAccordo e idCrmAccordo non valorizzati).');
            return;
        }

        Decimal scontoDc = (Decimal) oi.get('SIAE_DCDiscountPercent__c');
        Decimal scontoDda = (Decimal) oi.get('SIAE_DDADiscountPercent__c');
        accordo.percentualeScontoDc = fractionToIntegerPercent(scontoDc);
        accordo.percentualeScontoDda = fractionToIntegerPercent(scontoDda);

        buildResult.assumptions.add('accordo.percentualeScontoDc valorizzato da OrderItem.SIAE_DCDiscountPercent__c (frazione 0-1 convertita in percentuale intera per SPORT, 0 incluso).');
        buildResult.assumptions.add('accordo.percentualeScontoDda valorizzato da OrderItem.SIAE_DDADiscountPercent__c (frazione 0-1 convertita in percentuale intera per SPORT, 0 incluso).');
    }

    private static void resolveGenereLocale(
        OrderItem oi,
        SalvaSchedaBuildResult buildResult
    ) {
        String genereName = oi == null ? null : oi.SIAE_GenereName__c;
        String productCode = oi == null || oi.Product2 == null ? null : oi.Product2.ProductCode;

        if (String.isBlank(genereName)) { buildResult.warnings.add('Codice locale SIAE non risolto: OrderItem.SIAE_GenereName__c non valorizzato.'); return; }

        if (String.isBlank(productCode)) { buildResult.warnings.add('Codice locale SIAE non risolto: Product2.ProductCode non valorizzato.'); return; }

        try {
            buildResult.resolvedGenereLocaleCode =
                SIAE_UTIL_GenereLocaleConfig.getGenereCode(genereName, productCode);

            buildResult.assumptions.add(
                'Codice locale SIAE risolto da SIAE_UTIL_GenereLocaleConfig.getGenereCode(nomeGenere, productCode) ' +
                'ma non serializzato nella request Swagger: ' +
                buildResult.resolvedGenereLocaleCode
            );
        } catch (Exception ex) {
            buildResult.warnings.add(
                'Codice locale SIAE non risolto tramite SIAE_UTIL_GenereLocaleConfig per Genere=' +
                genereName + ', ProductCode=' + productCode + '. Dettaglio: ' + ex.getMessage()
            );
        }
    }

    private static List<Parametro> buildSchedaParametriFromOrderItemAttributes(
        OrderItem oi,
        SalvaSchedaBuildResult buildResult
    ) {
        List<Parametro> result = new List<Parametro>();

        if (oi == null || oi.Id == null) { addMissingParameter(buildResult, 'scheda.parametri[]: impossibile leggere OrderItemAttribute perché OrderItem nullo.'); return result; }

        String valueFieldName = resolveOrderItemAttributeValueFieldName();
        if (String.isBlank(valueFieldName)) { addMissingParameter(buildResult, 'scheda.parametri[]: impossibile individuare il campo valore su OrderItemAttribute.'); return result; }

        /*
         * I valori dei parametri di scheda devono sempre partire dagli
         * OrderItemAttribute dell'OrderItem corrente.
         *
         * Nota importante Automezzi:
         * per SIAE-PROD-AUTOMEZZI il parametro tipoAutomezzo è una inchiodatura
         * funzionale e non deve dipendere dalla risoluzione del genere locale.
         * Il valore SPORT si calcola direttamente dalla coppia:
         * - SIAE-ATTR-CLASS      -> tipo mezzo
         * - SIAE-ATTR-CILINDRATA -> cilindrata
         *
         * Questo evita che scheda.parametri[] resti vuoto quando
         * OrderItem.SIAE_GenereName__c non è valorizzato, pur essendo il prodotto
         * chiaramente Automezzi.
         */
        Map<String, String> attributeValueByCode =
            loadOrderItemAttributeValueByCode(oi.Id, valueFieldName, buildResult, 'scheda.parametri[]');

        if (
            oi.Product2 != null &&
            String.isNotBlank(oi.Product2.ProductCode) &&
            oi.Product2.ProductCode.trim().equalsIgnoreCase(PRODUCT_CODE_AUTOMEZZI)
        ) {
            String valoreTipoAutomezzo = resolveTipoAutomezzoSchedaParametro(
                attributeValueByCode,
                buildResult,
                SIAE_UTIL_GenereLocaleConfig.PARAM_TIPO_AUTOMEZZO
            );

            if (String.isBlank(valoreTipoAutomezzo)) {
                addMissingParameter(
                    buildResult,
                    'scheda.parametri[tipoAutomezzo]: valore non risolto per prodotto ' +
                    PRODUCT_CODE_AUTOMEZZI +
                    '. Verificare OrderItemAttribute SIAE-ATTR-CLASS e SIAE-ATTR-CILINDRATA.'
                );
                return result;
            }

            result.add(new Parametro(
                SIAE_UTIL_GenereLocaleConfig.PARAM_TIPO_AUTOMEZZO,
                valoreTipoAutomezzo.trim()
            ));

            buildResult.assumptions.add(
                'scheda.parametri[] valorizzato con inchiodatura Automezzi: Product2.ProductCode = ' +
                PRODUCT_CODE_AUTOMEZZI +
                ', parametro tipoAutomezzo risolto tramite SIAE_UTIL_GenereLocaleConfig.resolveTipoAutomezzo(...) ' +
                'usando SIAE-ATTR-CLASS e SIAE-ATTR-CILINDRATA.'
            );

            return result;
        }

        List<SIAE_GenereLocaleParameter__mdt> parameterRows =
            getSchedaAndLocaleParameterRows(buildResult.resolvedGenereLocaleCode, buildResult);
        
        if (parameterRows.isEmpty()) {
            buildResult.assumptions.add(
                'scheda.parametri[] lasciato vuoto: nessun SIAE_GenereLocaleParameter__mdt con Scope = LOCALE/SCHEDA trovato per genere = ' +
                String.valueOf(buildResult.resolvedGenereLocaleCode) +
                ' / fallback ALL. Lista vuota ammessa.'
            );
            return result;
        }

        /*
         * Per i prodotti diversi da Automezzi, i parametri di scheda sono
         * alimentati esclusivamente dai record SIAE_GenereLocaleParameter__mdt
         * con Scope = SCHEDA.
         *
         * Per ogni record:
         * - se il parametro è una picklist/enumeration, il valore Salesforce
         *   letto da OrderItemAttribute viene tradotto verso il valore SPORT
         *   tramite SIAE_UTIL_GenereLocaleConfig.resolveOutboundValue(...);
         * - se non è una picklist, viene usato il valore grezzo presente sul
         *   campo value dell'OrderItemAttribute.
         */
        Map<String, Parametro> parametroByName = new Map<String, Parametro>();

        for (SIAE_GenereLocaleParameter__mdt row : parameterRows) {
            if (row == null) { continue; }

            if (String.isBlank(row.SIAE_ParameterName__c)) { buildResult.warnings.add('Metadata SCHEDA ' + row.DeveloperName + ': SIAE_ParameterName__c non valorizzato.'); continue;}

            String nomeParametro = row.SIAE_ParameterName__c.trim();
            String valoreParametro = resolveSchedaParametroValue(
                oi,
                row,
                attributeValueByCode,
                buildResult
            );

            if (String.isBlank(valoreParametro)) {
                if (row.SIAE_IsRequired__c == true) {
                    addMissingParameter(
                        buildResult,
                        'scheda.parametri[' + nomeParametro + ']: valore non trovato o non risolvibile da OrderItemAttribute/metadata SCHEDA.'
                    );
                } else {
                    buildResult.warnings.add(
                        'scheda.parametri[' + nomeParametro + ']: valore non trovato o non risolvibile da OrderItemAttribute/metadata SCHEDA.'
                    );
                }
                continue;
            }

            parametroByName.put(nomeParametro, new Parametro(nomeParametro, normalizeIntegerParametroValue(valoreParametro.trim())));
        }

        List<String> sortedNames = new List<String>(parametroByName.keySet());
        sortedNames.sort();

        for (String nome : sortedNames) { result.add(parametroByName.get(nome)); }

        if (result.isEmpty()) {
            buildResult.assumptions.add(
                'scheda.parametri[] lasciato vuoto: metadata SCHEDA presenti ma nessun parametro valorizzato/generato. Lista vuota ammessa.'
            );
        } else {
            buildResult.assumptions.add(
                'scheda.parametri[] valorizzato da SIAE_GenereLocaleParameter__mdt con Scope = LOCALE/SCHEDA. ' +
                'Per i parametri enumeration viene letto il valore Salesforce da OrderItemAttribute e tradotto tramite ' +
                'SIAE_UTIL_GenereLocaleConfig.resolveOutboundValue(...). ' +
                'Se il valore runtime non è presente viene usato SIAE_DefaultValue__c quando configurato.'
            );
        }

        return result;
    }

    /**
     * Risolve il valore outbound di un singolo parametro SCHEDA.
     *
     * La logica è volutamente isolata dal resto della request perché riguarda
     * solo scheda.parametri[].valore e non deve impattare strumenti, costi o
     * altri mapping tariffari.
     */
    private static String resolveSchedaParametroValue(
        OrderItem oi,
        SIAE_GenereLocaleParameter__mdt row,
        Map<String, String> attributeValueByCode,
        SalvaSchedaBuildResult buildResult
    ) {
        if (row == null) {
            return null;
        }
    
        String nomeParametro = row.SIAE_ParameterName__c == null
            ? null
            : row.SIAE_ParameterName__c.trim();
    
        /*
         * Inchiodatura Automezzi:
         * solo per SIAE-PROD-AUTOMEZZI e solo per il parametro tipoAutomezzo
         * il valore SPORT non deriva da un unico attributo, ma dalla combinazione
         * del tipo mezzo e della cilindrata.
         */
        if (isAutomezziTipoAutomezzoParameter(oi, row, nomeParametro)) {
            return resolveTipoAutomezzoSchedaParametro(
                attributeValueByCode,
                buildResult,
                nomeParametro
            );
        }
    
        /*
         * Allineamento con CreateLocale:
         * utilizzoNave deriva dalla combinazione tipo nave + passeggeri.
         */
        if (
            String.isNotBlank(nomeParametro) &&
            SIAE_UTIL_GenereLocaleConfig.PARAM_UTILIZZO_NAVE.equalsIgnoreCase(nomeParametro)
        ) {
            String tipoNave = attributeValueByCode == null
                ? null
                : attributeValueByCode.get(normalizeKey(SIAE_UTIL_GenereLocaleConfig.ATTR_TIPO_NAVE));
    
            String passeggeri = attributeValueByCode == null
                ? null
                : attributeValueByCode.get(normalizeKey(SIAE_UTIL_GenereLocaleConfig.ATTR_PASSEGGERI));
    
            if (String.isNotBlank(tipoNave) && String.isNotBlank(passeggeri)) {
                try {
                    return SIAE_UTIL_GenereLocaleConfig.resolveUtilizzoNave(tipoNave, passeggeri);
                } catch (Exception ex) {
                    if (buildResult != null) {
                        buildResult.warnings.add(
                            'scheda.parametri[' + String.valueOf(nomeParametro) +
                            ']: utilizzoNave non risolto. Dettaglio: ' + ex.getMessage()
                        );
                    }
                    return null;
                }
            }
    
            if (String.isNotBlank(row.SIAE_DefaultValue__c)) {
                return row.SIAE_DefaultValue__c.trim();
            }
    
            return null;
        }
    
        String attributeCode = row.SIAE_AttributeDefinitionCode__c;
    
        /*
         * Allineamento con CreateLocale:
         * parametro metadata-only senza AttributeDefinitionCode.
         * Prima usa SIAE_DefaultValue__c; poi, per retrocompatibilità con la logica
         * già presente in SalvaScheda, usa il primo valore enum configurato.
         */
        if (String.isBlank(attributeCode)) {
            if (String.isNotBlank(row.SIAE_DefaultValue__c)) {
                return row.SIAE_DefaultValue__c.trim();
            }
    
            if (hasConfiguredEnumValue(row)) {
                return getFirstConfiguredEnumValue(row);
            }
    
            if (buildResult != null) {
                buildResult.warnings.add(
                    'scheda.parametri[' + String.valueOf(nomeParametro) +
                    ']: metadata ' + String.valueOf(row.SIAE_Scope__c) +
                    ' senza SIAE_AttributeDefinitionCode__c e senza valore default/enum configurato.'
                );
            }
    
            return null;
        }
    
        String sfRawValue = attributeValueByCode == null
            ? null
            : attributeValueByCode.get(normalizeKey(attributeCode));
    
        /*
         * Allineamento con CreateLocale:
         * valore runtime assente -> fallback al default se configurato.
         */
        if (String.isBlank(sfRawValue)) {
            if (String.isNotBlank(row.SIAE_DefaultValue__c)) {
                return row.SIAE_DefaultValue__c.trim();
            }
    
            return null;
        }
    
        /*
         * Picklist/enumeration:
         * il valore Salesforce può non coincidere con quello SPORT.
         */
        if (isEnumerationParameter(row)) {
            try {
                return SIAE_UTIL_GenereLocaleConfig.resolveOutboundValue(row, sfRawValue);
            } catch (Exception ex) {
                if (buildResult != null) {
                    buildResult.warnings.add(
                        'scheda.parametri[' + String.valueOf(nomeParametro) +
                        ']: valore picklist Salesforce "' + sfRawValue +
                        '" non risolto verso SPORT. Dettaglio: ' + ex.getMessage()
                    );
                }
                return null;
            }
        }
    
        /*
         * Parametro non picklist:
         * viene usato il valore runtime dell'OrderItemAttribute così com'è.
         */
        return sfRawValue;
    }

    private static Boolean isEnumerationParameter(SIAE_GenereLocaleParameter__mdt row) {
        return row != null && String.isNotBlank(row.SIAE_DataType__c) && row.SIAE_DataType__c.trim().equalsIgnoreCase(DATA_TYPE_ENUMERATION);
    }

    private static Boolean isAutomezziTipoAutomezzoParameter(
        OrderItem oi,
        SIAE_GenereLocaleParameter__mdt row,
        String nomeParametro
    ) {
        if (oi == null || oi.Product2 == null || String.isBlank(oi.Product2.ProductCode)) { return false; }

        if (!oi.Product2.ProductCode.trim().equalsIgnoreCase(PRODUCT_CODE_AUTOMEZZI)) { return false; }

        return isEnumerationParameter(row) && String.isNotBlank(nomeParametro) && SIAE_UTIL_GenereLocaleConfig.PARAM_TIPO_AUTOMEZZO.equalsIgnoreCase(nomeParametro);
    }

    private static String resolveTipoAutomezzoSchedaParametro(
        Map<String, String> attributeValueByCode,
        SalvaSchedaBuildResult buildResult,
        String nomeParametro
    ) {
        String tipoMezzo = attributeValueByCode == null ? null : attributeValueByCode.get(normalizeKey(SIAE_UTIL_GenereLocaleConfig.ATTR_TIPO_MEZZO));

        String cilindrata = attributeValueByCode == null ? null : attributeValueByCode.get(normalizeKey(SIAE_UTIL_GenereLocaleConfig.ATTR_CILINDRATA));

        if (String.isBlank(tipoMezzo)) { return null; }

        try {
            return SIAE_UTIL_GenereLocaleConfig.resolveTipoAutomezzo(tipoMezzo, cilindrata);
        } catch (Exception ex) {
            if (buildResult != null) { buildResult.warnings.add('scheda.parametri[' + String.valueOf(nomeParametro) + ']: tipoAutomezzo non risolto per SIAE-PROD-AUTOMEZZI. Dettaglio: ' + ex.getMessage() ); }
            return null;
        }
    }


/**
     * Restituisce una mappa AttributeDefinition.Code -> valore OrderItemAttribute.
     *
     * La lettura usa OrderItemAttribute e AttributeDefinition già in cache; in
     * questo modo scheda.parametri, scheda.strumenti e fallback instrumentId non
     * ripetono le stesse query.
     */
    private static Map<String, String> loadOrderItemAttributeValueByCode(
        Id orderItemId,
        String valueFieldName,
        SalvaSchedaBuildResult buildResult,
        String contextLabel
    ) {
        Map<String, String> result = new Map<String, String>();

        Map<String, String> testValuesByCode = getTestOrderItemAttributeValuesByCode(orderItemId);
        if (testValuesByCode != null) { return testValuesByCode; }

        if (orderItemId == null || String.isBlank(valueFieldName)) { return result; }

        List<SObject> orderItemAttributes = getOrderItemAttributes(
            orderItemId,
            valueFieldName,
            buildResult,
            contextLabel
        );

        if (orderItemAttributes.isEmpty()) { return result; }

        for (SObject oia : orderItemAttributes) {
            String attributeDefinitionId = asString(oia.get('AttributeDefinitionId'));
            if (String.isBlank(attributeDefinitionId)) { continue; }

            SObject ad = attributeDefinitionByIdCache.get(attributeDefinitionId);
            if (ad == null) {
                if (buildResult != null) { buildResult.warnings.add(contextLabel + ': AttributeDefinition non trovato per OrderItemAttribute ' + asString(oia.get('Id')) + '.'); }
                continue;
            }

            String attributeCode = asString(safeGet(ad, 'Code'));
            if (String.isBlank(attributeCode)) {
                if (buildResult != null) { buildResult.warnings.add(contextLabel + ': AttributeDefinition.Code non valorizzato per OrderItemAttribute ' + asString(oia.get('Id')) + '.'); }
                continue;
            }

            String rawValue = asString(oia.get(valueFieldName));
            if (String.isNotBlank(rawValue)) { result.put(normalizeKey(attributeCode),rawValue.trim()); }
        }

        return result;
    }

    /**
     * Recupera OrderItemAttribute da cache; se mancano, li carica in bulk per
     * gli OrderItem richiesti e precarica anche le AttributeDefinition collegate.
     */
    private static List<SObject> getOrderItemAttributes(
        Id orderItemId,
        String valueFieldName,
        SalvaSchedaBuildResult buildResult,
        String contextLabel
    ) {
        if (orderItemId == null || String.isBlank(valueFieldName)) { return new List<SObject>(); }

        preloadOrderItemAttributes(new Set<Id>{ orderItemId }, valueFieldName, buildResult, contextLabel);

        if (!orderItemAttributesByOrderItemIdCache.containsKey(orderItemId)) { return new List<SObject>(); }
        return orderItemAttributesByOrderItemIdCache.get(orderItemId);
    }

    /**
     * Precarica gli OrderItemAttribute per un set di OrderItemId.
     *
     * Il metodo è idempotente: un OrderItemId già precaricato non viene più
     * interrogato nella stessa transazione.
     */
    private static void preloadOrderItemAttributes(
        Set<Id> orderItemIds,
        String valueFieldName,
        SalvaSchedaBuildResult buildResult,
        String contextLabel
    ) {
        if (orderItemIds == null || orderItemIds.isEmpty() || String.isBlank(valueFieldName)) { return; }

        Set<Id> idsToLoad = new Set<Id>();
        for (Id orderItemId : orderItemIds) {
            if (orderItemId == null) { continue; }
            if (!preloadedOrderItemAttributeOrderItemIds.contains(orderItemId)) {
                idsToLoad.add(orderItemId);
                orderItemAttributesByOrderItemIdCache.put(orderItemId, new List<SObject>());
            }
        }

        if (idsToLoad.isEmpty()) { return; }

        List<SObject> orderItemAttributes = Database.query(
            'SELECT Id, OrderItemId, AttributeDefinitionId, ' + valueFieldName + ' ' +
            'FROM OrderItemAttribute ' +
            'WHERE OrderItemId IN :idsToLoad'
        );

        Set<Id> attributeDefinitionIds = new Set<Id>();
        for (SObject oia : orderItemAttributes) {
            Id currentOrderItemId = (Id) oia.get('OrderItemId');
            if (!orderItemAttributesByOrderItemIdCache.containsKey(currentOrderItemId)) { orderItemAttributesByOrderItemIdCache.put(currentOrderItemId,new List<SObject>()); }
            orderItemAttributesByOrderItemIdCache.get(currentOrderItemId).add(oia);

            Object adIdValue = oia.get('AttributeDefinitionId');
            if (adIdValue != null) { attributeDefinitionIds.add((Id) adIdValue); }
        }

        preloadAttributeDefinitions(attributeDefinitionIds);
        preloadedOrderItemAttributeOrderItemIds.addAll(idsToLoad);

        if (buildResult != null && String.isNotBlank(contextLabel)) {
            for (Id loadedId : idsToLoad) {
                if (!orderItemAttributesByOrderItemIdCache.containsKey(loadedId) || orderItemAttributesByOrderItemIdCache.get(loadedId).isEmpty()) { buildResult.warnings.add(contextLabel + ': nessun OrderItemAttribute trovato per OrderItem ' + String.valueOf(loadedId) + '.'); }
            }
        }
    }

    /**
     * Precarica AttributeDefinition una sola volta per Id.
     */
    private static void preloadAttributeDefinitions(Set<Id> attributeDefinitionIds) {
        if (attributeDefinitionIds == null || attributeDefinitionIds.isEmpty()) { return; }

        Set<Id> idsToLoad = new Set<Id>();
        for (Id attributeDefinitionId : attributeDefinitionIds) {
            if (attributeDefinitionId == null) { continue; }
            if (!attributeDefinitionByIdCache.containsKey(String.valueOf(attributeDefinitionId))) { idsToLoad.add(attributeDefinitionId); }
        }

        if (idsToLoad.isEmpty()) { return; }

        for (SObject row : Database.query(
            'SELECT Id, Code ' +
            'FROM AttributeDefinition ' +
            'WHERE Id IN :idsToLoad'
        )) {
            attributeDefinitionByIdCache.put(asString(row.get('Id')), row);
        }
    }

    private static List<Strumento> buildStrumentiFromOrderItemAttributes(
        OrderItem oi,
        SalvaSchedaBuildResult buildResult
    ) {
        if (oi == null || oi.Id == null) { addMissingParameter(buildResult, 'scheda.strumenti: impossibile leggere OrderItemAttribute perché OrderItem nullo.');  return new List<Strumento>(); }

        String valueFieldName = resolveOrderItemAttributeValueFieldName();
        if (String.isBlank(valueFieldName)) { addMissingParameter(buildResult, 'OrderItemAttribute: impossibile individuare il campo valore dell’attributo. Verificare il campo runtime che contiene la quantità.'); return new List<Strumento>(); }

        Map<String, String> testAttributeValueByCode = getTestOrderItemAttributeValuesByCode(oi.Id);
        if (testAttributeValueByCode != null) { return buildStrumentiFromAttributeValueByCode(testAttributeValueByCode,buildResult); }

        List<SObject> orderItemAttributes = getOrderItemAttributes(
            oi.Id,
            valueFieldName,
            buildResult,
            'scheda.strumenti'
        );

        if (orderItemAttributes.isEmpty()) {
            addMissingParameter(buildResult, 'scheda.strumenti: nessun OrderItemAttribute trovato per OrderItem ' + String.valueOf(oi.Id) + '.');
            return new List<Strumento>();
        }

        Map<String, InstrumentAccumulator> accumulatorByKey = new Map<String, InstrumentAccumulator>();

        for (SObject oia : orderItemAttributes) {
            String rawValue = asString(oia.get(valueFieldName));
            Decimal numericValue = parseDecimalOrNull(rawValue);

            if (String.isBlank(rawValue)) { continue; }
            if (numericValue != null && numericValue == 0) { continue; }

            String attributeDefinitionId = asString(oia.get('AttributeDefinitionId'));
            if (String.isBlank(attributeDefinitionId)) { continue; }

            SObject ad = attributeDefinitionByIdCache.get(attributeDefinitionId);
            if (ad == null) { buildResult.warnings.add('OrderItemAttribute ' + asString(oia.get('Id')) + ': AttributeDefinition non trovato.'); continue; }

            String attributeCode = asString(safeGet(ad, 'Code'));
            if (String.isBlank(attributeCode)) { buildResult.warnings.add('OrderItemAttribute ' + asString(oia.get('Id')) + ': AttributeDefinition.Code non valorizzato.'); continue; }

            List<SIAE_GenereLocaleParameter__mdt> parameterRows =
                getStrumentoParameterRows(buildResult.resolvedGenereLocaleCode, attributeCode);

            if (parameterRows.isEmpty()) {
                buildResult.warnings.add(
                    'Nessun SIAE_GenereLocaleParameter__mdt STRUMENTO trovato per AttributeDefinition.Code = ' +
                    attributeCode + ', genere = ' + String.valueOf(buildResult.resolvedGenereLocaleCode) + ' / fallback ALL.'
                );
                continue;
            }

            if (numericValue == null && !hasStringParameterRow(parameterRows)) {
                buildResult.warnings.add(
                    'Attributo ' + attributeCode + ': valore "' + rawValue +
                    '" non numerico e nessun metadata STRUMENTO con SIAE_DataType__c = string. Attributo ignorato.'
                );
                continue;
            }

            applyStrumentoMetadataRows(accumulatorByKey, parameterRows, numericValue, rawValue, buildResult, attributeCode);
        }

        List<Strumento> strumenti = buildStrumentiFromAccumulators(accumulatorByKey, buildResult);
        if (strumenti.isEmpty()) { addMissingParameter(buildResult,'scheda.strumenti: nessuno strumento generato dagli attributi valorizzati.'); }

        buildResult.assumptions.add(
            'scheda.strumenti[] valorizzato da OrderItemAttribute usando campo valore: ' +
            valueFieldName + ' e metadata SIAE_GenereLocaleParameter__mdt.getAll().'
        );
        return strumenti;
    }


    private static List<Strumento> buildStrumentiFromAttributeValueByCode(
        Map<String, String> attributeValueByCode,
        SalvaSchedaBuildResult buildResult
    ) {
        Map<String, InstrumentAccumulator> accumulatorByKey = new Map<String, InstrumentAccumulator>();

        if (attributeValueByCode == null || attributeValueByCode.isEmpty()) { addMissingParameter(buildResult, 'scheda.strumenti: nessuno strumento generato dagli attributi valorizzati.'); return new List<Strumento>();}

        List<String> attributeCodes = new List<String>(attributeValueByCode.keySet());
        attributeCodes.sort();

        for (String attributeCode : attributeCodes) {
            String rawValue = attributeValueByCode.get(attributeCode);
            Decimal numericValue = parseDecimalOrNull(rawValue);

            if (String.isBlank(rawValue)) { continue; }
            if (numericValue != null && numericValue == 0) { continue; }

            List<SIAE_GenereLocaleParameter__mdt> parameterRows =
                getStrumentoParameterRows(buildResult.resolvedGenereLocaleCode, attributeCode);

            if (parameterRows.isEmpty()) {
                buildResult.warnings.add(
                    'Nessun SIAE_GenereLocaleParameter__mdt STRUMENTO trovato per AttributeDefinition.Code = ' +
                    attributeCode + ', genere = ' + String.valueOf(buildResult.resolvedGenereLocaleCode) + ' / fallback ALL.'
                );
                continue;
            }

            if (numericValue == null && !hasStringParameterRow(parameterRows)) {
                buildResult.warnings.add(
                    'Attributo ' + attributeCode + ': valore "' + rawValue +
                    '" non numerico e nessun metadata STRUMENTO con SIAE_DataType__c = string. Attributo ignorato.'
                );
                continue;
            }

            applyStrumentoMetadataRows(accumulatorByKey, parameterRows, numericValue, rawValue, buildResult, attributeCode);
        }

        List<Strumento> strumenti = buildStrumentiFromAccumulators(accumulatorByKey, buildResult);
        if (strumenti.isEmpty()) { addMissingParameter(buildResult,'scheda.strumenti: nessuno strumento generato dagli attributi valorizzati.'); }

        buildResult.assumptions.add('scheda.strumenti[] valorizzato da attributi iniettati in test tramite @TestVisible.');
        return strumenti;
    }

    private static void applyStrumentoMetadataRows(
        Map<String, InstrumentAccumulator> accumulatorByKey,
        List<SIAE_GenereLocaleParameter__mdt> parameterRows,
        Decimal attributeValue,
        String rawValue,
        SalvaSchedaBuildResult buildResult,
        String attributeCode
    ) {
        String idStrumento = null;
        Map<String, String> fixedParams = new Map<String, String>();

        for (SIAE_GenereLocaleParameter__mdt row : parameterRows) {
            if (String.isBlank(row.SIAE_IdStrumento__c)) { buildResult.warnings.add('Metadata STRUMENTO ' + row.DeveloperName + ' per attributo ' + attributeCode + ': SIAE_IdStrumento__c non valorizzato.'); continue; }

            if (idStrumento == null) { idStrumento = row.SIAE_IdStrumento__c; } else if (idStrumento != row.SIAE_IdStrumento__c) {
                buildResult.warnings.add(
                    'Attributo ' + attributeCode + ': trovati più SIAE_IdStrumento__c nei metadata STRUMENTO. ' +
                    'Valore iniziale = ' + idStrumento + ', valore scartato = ' + row.SIAE_IdStrumento__c + ', record = ' + row.DeveloperName
                );
                continue;
            }

            if (isFixedParameter(row)) {
                String fixedValue = getFixedParameterValue(row);
                if (String.isNotBlank(row.SIAE_ParameterName__c) && String.isNotBlank(fixedValue)) { fixedParams.put(row.SIAE_ParameterName__c, fixedValue); }
            }
        }

        if (String.isBlank(idStrumento)) { buildResult.warnings.add('Attributo ' + attributeCode + ': impossibile generare strumento perché nessun metadata ha SIAE_IdStrumento__c valorizzato.'); return; }

        String nomeStrumento = resolveNomeStrumento(parameterRows, idStrumento, buildResult, attributeCode);
        String groupKey = buildInstrumentGroupKey(idStrumento, fixedParams);

        if (!accumulatorByKey.containsKey(groupKey)) {
            InstrumentAccumulator acc = new InstrumentAccumulator();
            acc.idStrumento = idStrumento;
            acc.nomeStrumento = nomeStrumento;

            for (String fixedName : fixedParams.keySet()) {
                acc.addFixedParametro(fixedName, fixedParams.get(fixedName));
            }
            accumulatorByKey.put(groupKey, acc);
        } else {
            InstrumentAccumulator existing = accumulatorByKey.get(groupKey);
            if (String.isBlank(existing.nomeStrumento) && String.isNotBlank(nomeStrumento)) { existing.nomeStrumento = nomeStrumento; } else if (String.isNotBlank(existing.nomeStrumento) && String.isNotBlank(nomeStrumento) && existing.nomeStrumento != nomeStrumento) {
                buildResult.warnings.add(
                    'Attributo ' + attributeCode + ': nome strumento non coerente per idStrumento ' + idStrumento +
                    '. Valore già presente = ' + existing.nomeStrumento + ', valore metadata = ' + nomeStrumento
                );
            }
        }

        InstrumentAccumulator current = accumulatorByKey.get(groupKey);
        current.addAttributeCode(attributeCode);

        for (SIAE_GenereLocaleParameter__mdt row : parameterRows) {
            if (String.isBlank(row.SIAE_ParameterName__c)) {  buildResult.warnings.add('Metadata STRUMENTO ' + row.DeveloperName + ' per attributo ' + attributeCode + ': SIAE_ParameterName__c non valorizzato.'); continue; }

            if (row.SIAE_IdStrumento__c != idStrumento) { continue; }

            if (isFixedParameter(row)) {
                String fixedValue = getFixedParameterValue(row);
                if (String.isNotBlank(fixedValue)) { current.addFixedParametro(row.SIAE_ParameterName__c, fixedValue); }
                continue;
            }

            if (isStringParameter(row)) {
                String textValue = resolveStringParameterValue(row, rawValue, buildResult, attributeCode);
                if (String.isNotBlank(textValue)) { current.addTextParametro(row.SIAE_ParameterName__c, textValue); }
                continue;
            }

            current.addQuantityParametro(row.SIAE_ParameterName__c, attributeValue);
        }
    }

    private static String resolveNomeStrumento(
        List<SIAE_GenereLocaleParameter__mdt> parameterRows,
        String idStrumento,
        SalvaSchedaBuildResult buildResult,
        String attributeCode
    ) {
        if (parameterRows == null || parameterRows.isEmpty() || String.isBlank(idStrumento)) { return null; }

        Set<String> nomi = new Set<String>();

        for (SIAE_GenereLocaleParameter__mdt row : parameterRows) {
            if (row == null || row.SIAE_IdStrumento__c != idStrumento) { continue; }
            if (String.isNotBlank(row.SIAE_NomeStrumento__c)) { nomi.add(row.SIAE_NomeStrumento__c.trim()); }
        }

        if (nomi.isEmpty()) {
            buildResult.warnings.add( 'Attributo ' + attributeCode + ': SIAE_NomeStrumento__c non valorizzato nei metadata per idStrumento ' + idStrumento + '. Il JSON resta comunque valido perché lo Swagger richiede solo idStrumento.' );
            return null;
        }

        List<String> sortedNames = new List<String>(nomi);
        sortedNames.sort();

        if (sortedNames.size() > 1) { buildResult.warnings.add('Attributo ' + attributeCode + ': trovati più nomi strumento per idStrumento ' + idStrumento + ': ' + String.join(sortedNames,', ') + '. Applicato il primo in ordine alfabetico.' ); }

        return sortedNames[0];
    }

    private static List<Strumento> buildStrumentiFromAccumulators(
        Map<String, InstrumentAccumulator> accumulatorByKey,
        SalvaSchedaBuildResult buildResult
    ) {
        List<Strumento> strumenti = new List<Strumento>();
        List<String> sortedKeys = new List<String>(accumulatorByKey.keySet());
        sortedKeys.sort();

        for (String key : sortedKeys) {
            InstrumentAccumulator acc = accumulatorByKey.get(key);
            Strumento s = new Strumento();
            s.idStrumento = acc.idStrumento;
            s.parametri = new List<Parametro>();

            List<String> quantityNames = new List<String>(acc.quantityParams.keySet());
            quantityNames.sort();
            for (String nomeParametro : quantityNames) {
                s.parametri.add(new Parametro(nomeParametro, formatQuantity(acc.quantityParams.get(nomeParametro))));
            }

            List<String> fixedNames = new List<String>(acc.fixedParams.keySet());
            fixedNames.sort();
            for (String fixedName : fixedNames) {
                s.parametri.add(new Parametro(fixedName, acc.fixedParams.get(fixedName)));
            }

            List<String> textNames = new List<String>(acc.textParams.keySet());
            textNames.sort();
            for (String textName : textNames) {
                s.parametri.add(new Parametro(textName, acc.textParams.get(textName)));
            }

            if (!s.parametri.isEmpty()) {
                strumenti.add(s);
                if (buildResult != null) { buildResult.strumentiAttributeCodes.add(acc.attributeCodes); }
            }
        }

        return strumenti;
    }

    /**
     * Compatibilità interna: restituisce AttributeDefinition usando la cache.
     */
    private static Map<String, SObject> loadAttributeDefinitions(Set<Id> attributeDefinitionIds) {
        preloadAttributeDefinitions(attributeDefinitionIds);

        Map<String, SObject> result = new Map<String, SObject>();
        if (attributeDefinitionIds == null) { return result; }

        for (Id attributeDefinitionId : attributeDefinitionIds) {
            String key = String.valueOf(attributeDefinitionId);
            if (attributeDefinitionByIdCache.containsKey(key)) { result.put(key,attributeDefinitionByIdCache.get(key)); }
        }
        return result;
    }

    /**
     * Deserializza OrderItem.SIAE_PaymentItems__c una sola volta per OrderItem.
     *
     * Il wrapper viene riusato da tariffa.vociCosto[], tariffa.altriCosti[] e
     * tariffa.costiStrumenti[], evitando parsing JSON duplicati.
     */
    private static PricingPaymentItem.Wrapper getPaymentWrapperFromOrderItem(
        OrderItem oi,
        SalvaSchedaBuildResult buildResult,
        String contextLabel,
        Boolean missingOnError
    ) {
        if (oi == null || oi.Id == null) {  addBuildMessage( buildResult, contextLabel + ': impossibile leggere SIAE_PaymentItems__c perché OrderItem nullo.', missingOnError ); return null; }

        if (paymentWrapperByOrderItemIdCache.containsKey(oi.Id)) { return paymentWrapperByOrderItemIdCache.get(oi.Id); }

        String rawPaymentItems = asString(oi.get('SIAE_PaymentItems__c'));
        if (String.isBlank(rawPaymentItems)) { addBuildMessage( buildResult, contextLabel + ': OrderItem.SIAE_PaymentItems__c non valorizzato.', missingOnError ); return null; }

        try {
            PricingPaymentItem.Wrapper paymentWrapper = parsePaymentWrapper(rawPaymentItems);

            paymentWrapperByOrderItemIdCache.put(oi.Id, paymentWrapper);

            if (paymentWrapper == null || paymentWrapper.paymentItems == null || paymentWrapper.paymentItems.isEmpty()) { addBuildMessage(buildResult,contextLabel + ': OrderItem.SIAE_PaymentItems__c non contiene paymentItems.',missingOnError ); }

            return paymentWrapper;
        } catch (Exception ex) {
            addBuildMessage( buildResult, contextLabel + ': impossibile deserializzare OrderItem.SIAE_PaymentItems__c. Dettaglio: ' + ex.getMessage(), missingOnError );
            return null;
        }
    }

    /**
     * Carica una sola volta il Custom Setting di priorità attributi.
     *
     * Si usa getAll() perché è un List Custom Setting e non serve consumare SOQL
     * per una configurazione statica di priorità.
     */
    private static List<InstrumentPriorityRow> getInstrumentPriorityRows() {
        if (instrumentPriorityRowsCache != null) { return instrumentPriorityRowsCache; }

        instrumentPriorityRowsCache = new List<InstrumentPriorityRow>();

        for (SIAE_InstrumentPriority__c row : SIAE_InstrumentPriority__c.getAll().values()) {
            if (row == null || String.isBlank(row.SIAE_AttributeCode__c)) { continue; }

            InstrumentPriorityRow priorityRow = new InstrumentPriorityRow();
            priorityRow.name = row.Name;
            priorityRow.attributeCode = row.SIAE_AttributeCode__c.trim();
            priorityRow.priority = row.SIAE_Priority__c;
            instrumentPriorityRowsCache.add(priorityRow);
        }

        instrumentPriorityRowsCache.sort();
        return instrumentPriorityRowsCache;
    }

    /**
     * Costruisce tariffa.costiStrumenti[] con un elemento per ogni occorrenza
     * di scheda.strumenti[] (non deduplicato per idStrumento), come si aspetta
     * SPORT. Ogni elemento ha sempre sia costiDda sia costiDc valorizzati,
     * eventualmente con vociCosto a importo 0, per poter mostrare lo
     * specchietto di dettaglio per ogni strumento. Eccezione: costiDc e' null
     * per gli strumenti senza PaymentItem DC (nessuna voce DC, ne' reale ne'
     * a importo 0), es. Jukebox o strumenti per cui il pricing non genera DC.
     *
     * Regole di attribuzione (allineate al comportamento osservato in SPORT):
     * - PaymentItem DDA/DC non FLAT: raggruppati per instrumentId (dal
     *   PaymentItem o, se assente, dal fallback SIAE_StrumentoPriority__c).
     *   Quando piu' occorrenze di scheda.strumenti condividono lo stesso
     *   idStrumento, si prova prima ad abbinare ogni PaymentItem alla
     *   occorrenza generata dallo stesso attributo (PaymentItem.attributeCode);
     *   se l'abbinamento non e' univocamente determinabile, l'ULTIMA
     *   occorrenza riceve i PaymentItem reali e le occorrenze precedenti
     *   ricevono le stesse vociCosto (per itemCode) con importo 0.
     * - PaymentItem DC FLAT: concettualmente "di scheda", non per strumento.
     *   Vengono aggregati per itemCode su tutti gli strumenti e il totale
     *   reale viene assegnato alla PRIMA occorrenza di scheda.strumenti[] non
     *   in STRUMENTI_SENZA_DC; le altre occorrenze non in STRUMENTI_SENZA_DC
     *   ricevono le stesse vociCosto con importo 0.
     */
    private static List<CostiStrumento> buildCostiStrumentiFromPaymentItems(
        List<Strumento> strumenti,
        OrderItem oi,
        SalvaSchedaBuildResult buildResult
    ) {
        List<CostiStrumento> slots = new List<CostiStrumento>();
        Map<String, List<Integer>> slotIndexesByInstrumentId = new Map<String, List<Integer>>();

        Boolean dirittiConnessiPrevisti = hasDirittiConnessi(oi);

        if (strumenti != null) {
            for (Strumento strumento : strumenti) {
                if (strumento == null || String.isBlank(strumento.idStrumento)) { continue; }

                String instrumentId = strumento.idStrumento.trim();

                CostiStrumento costo = new CostiStrumento();
                costo.idStrumento = instrumentId;
                costo.costiDda = initializeDettaglioCosto();
                costo.costiDc = dirittiConnessiPrevisti ? initializeDettaglioCosto() : null;

                if (!slotIndexesByInstrumentId.containsKey(instrumentId)) { slotIndexesByInstrumentId.put(instrumentId, new List<Integer>()); }
                slotIndexesByInstrumentId.get(instrumentId).add(slots.size());

                slots.add(costo);
            }
        }

        if (oi == null || oi.Id == null) { buildResult.warnings.add('tariffa.costiStrumenti[]: impossibile leggere SIAE_PaymentItems__c perché OrderItem nullo.'); return buildCostiStrumentiResult(slots); }

        PricingPaymentItem.Wrapper paymentWrapper = getPaymentWrapperFromOrderItem(
            oi,
            buildResult,
            'tariffa.costiStrumenti[]',
            false
        );

        if (paymentWrapper == null || paymentWrapper.paymentItems == null || paymentWrapper.paymentItems.isEmpty()) { return buildCostiStrumentiResult(slots); }

        String fallbackInstrumentId = resolveFallbackInstrumentIdForCostiStrumenti(oi, buildResult);

        Integer ddaMapped = 0;
        Integer dcMapped = 0;
        Integer fallbackInstrumentIdApplied = 0;

        Boolean negoziApparecchioOverride = isNegoziSottoSogliaMqAreeVendita(oi, buildResult);

        Map<String, List<PricingPaymentItem>> perInstrumentItemsByGroupKey =
            new Map<String, List<PricingPaymentItem>>();
        List<PricingPaymentItem> dcFlatItems = new List<PricingPaymentItem>();

        for (PricingPaymentItem item : paymentWrapper.paymentItems) {
            if (item == null || !isRevenueCostPaymentItem(item)) { continue; }

            Boolean isDdaItem = item.type != null && item.type.trim().equalsIgnoreCase('DDA');
            if (!isDdaItem && !dirittiConnessiPrevisti) {
                /*
                 * Licenza senza diritti connessi (OrderItem.SIAE_DirittiConnessi__c
                 * non valorizzato o pari a 0): i PaymentItem DC non vanno veicolati
                 * verso SPORT, coerentemente con scheda.statoDc e tariffa.dc.
                 */
                continue;
            }

            String instrumentId = item.instrumentId;

            if (String.isBlank(instrumentId)) {
                if (String.isBlank(fallbackInstrumentId)) {
                    buildResult.warnings.add(
                        'tariffa.costiStrumenti[]: PaymentItem ' + String.valueOf(item.type) +
                        ' / itemCode=' + String.valueOf(item.itemCode) +
                        ' ignorato perché instrumentId non valorizzato e fallback da SIAE_StrumentoPriority__c non risolto.'
                    );
                    continue;
                }

                instrumentId = fallbackInstrumentId;
                fallbackInstrumentIdApplied++;
            }

            if (String.isBlank(item.itemCode)) { buildResult.warnings.add( 'tariffa.costiStrumenti[]: PaymentItem ' + String.valueOf(item.type) + ' ignorato perché itemCode non valorizzato.' );  continue; }

            Decimal amount = parseDecimalOrNull(item.amount);
            if (amount == null) { buildResult.warnings.add( 'tariffa.costiStrumenti[]: PaymentItem ' + item.itemCode + ' ignorato perché amount non numerico o non valorizzato: ' + String.valueOf(item.amount) ); continue; }

            instrumentId = instrumentId.trim();
            Boolean isDda = isDdaItem;

            if (!isDda && isFlatPaymentItem(item) && !negoziApparecchioOverride) {
                dcFlatItems.add(item);
                dcMapped++;
                continue;
            }

            String groupKey = instrumentId + '|' + (isDda ? 'DDA' : 'DC');
            if (!perInstrumentItemsByGroupKey.containsKey(groupKey)) { perInstrumentItemsByGroupKey.put(groupKey, new List<PricingPaymentItem>()); }
            perInstrumentItemsByGroupKey.get(groupKey).add(item);

            if (isDda) { ddaMapped++; } else { dcMapped++; }
        }

        /*
         * PaymentItem DDA/DC non FLAT: assegnati per idStrumento all'ultima
         * occorrenza di scheda.strumenti[] con quello stesso idStrumento;
         * le occorrenze precedenti ricevono placeholder a importo 0 per gli
         * stessi itemCode, cosi' da mostrare comunque la voce nello
         * specchietto di dettaglio.
         */
        for (String groupKey : perInstrumentItemsByGroupKey.keySet()) {
            List<PricingPaymentItem> items = perInstrumentItemsByGroupKey.get(groupKey);
            if (items == null || items.isEmpty()) { continue; }

            Integer separatorIndex = groupKey.lastIndexOf('|');
            String instrumentId = groupKey.substring(0, separatorIndex);
            Boolean isDda = 'DDA'.equals(groupKey.substring(separatorIndex + 1));

            List<Integer> instrumentSlotIndexes = slotIndexesByInstrumentId.get(instrumentId);

            if (instrumentSlotIndexes == null || instrumentSlotIndexes.isEmpty()) {
                /*
                 * PaymentItem con instrumentId non presente in scheda.strumenti[]
                 * (es. fallback risolto verso uno strumento non elencato):
                 * viene comunque esposto come elemento aggiuntivo in coda, per
                 * non perdere l'informazione.
                 */
                CostiStrumento extraSlot = new CostiStrumento();
                extraSlot.idStrumento = instrumentId;
                extraSlot.costiDda = initializeDettaglioCosto();
                extraSlot.costiDc = dirittiConnessiPrevisti ? initializeDettaglioCosto() : null;
                slots.add(extraSlot);
                instrumentSlotIndexes = new List<Integer>{ slots.size() - 1 };
                slotIndexesByInstrumentId.put(instrumentId, instrumentSlotIndexes);
            }

            Integer targetSlotIndex = instrumentSlotIndexes[instrumentSlotIndexes.size() - 1];

            /*
             * Quando piu' occorrenze condividono lo stesso idStrumento (es.
             * "Fino a 40"/"Maggiore di 40" pollici), proviamo ad abbinare ogni
             * PaymentItem alla occorrenza generata dallo stesso attributo
             * (PaymentItem.attributeCode == scheda.strumenti[].attributeCodes),
             * cosi' da non concentrare tutti gli importi reali sull'ultima
             * occorrenza. Se l'abbinamento non e' possibile (dato storico senza
             * attributeCode, o nessuna corrispondenza), si ricade sul
             * comportamento precedente: tutto sull'ultima occorrenza.
             */
            Map<Integer, List<PricingPaymentItem>> itemsBySlotIndex = matchItemsToSlotsByAttributeCode(
                items,
                instrumentSlotIndexes,
                buildResult
            );

            for (Integer slotIndex : instrumentSlotIndexes) {
                CostiStrumento slot = slots.get(slotIndex);
                DettaglioCosto dettaglio = isDda ? slot.costiDda : slot.costiDc;

                List<PricingPaymentItem> matchedItems = itemsBySlotIndex == null ? null : itemsBySlotIndex.get(slotIndex);

                if (itemsBySlotIndex != null) {
                    if (matchedItems != null && !matchedItems.isEmpty()) {
                        for (PricingPaymentItem item : matchedItems) {
                            addPaymentItemToDettaglioCosto(dettaglio, item, parseDecimalOrNull(item.amount), oi, isDda, negoziApparecchioOverride);
                        }
                    } else {
                        addZeroPlaceholderVociCosto(dettaglio, items, oi, isDda, negoziApparecchioOverride);
                    }
                } else if (slotIndex == targetSlotIndex) {
                    for (PricingPaymentItem item : items) {
                        addPaymentItemToDettaglioCosto(dettaglio, item, parseDecimalOrNull(item.amount), oi, isDda, negoziApparecchioOverride);
                    }
                } else {
                    addZeroPlaceholderVociCosto(dettaglio, items, oi, isDda, negoziApparecchioOverride);
                }
            }
        }

        /*
         * PaymentItem DC FLAT: concettualmente "di scheda". Il totale reale per
         * itemCode viene assegnato alla prima occorrenza di scheda.strumenti[]
         * non in STRUMENTI_SENZA_DC; le altre occorrenze ammesse ricevono le
         * stesse vociCosto a importo 0.
         */
        if (!dcFlatItems.isEmpty() && !slots.isEmpty()) {
            Map<String, PricingPaymentItem> flatTotalByItemCode = new Map<String, PricingPaymentItem>();
            Map<String, Decimal> flatAmountByItemCode = new Map<String, Decimal>();

            for (PricingPaymentItem item : dcFlatItems) {
                Decimal amount = parseDecimalOrNull(item.amount);
                if (amount == null || String.isBlank(item.itemCode)) { continue; }

                if (!flatTotalByItemCode.containsKey(item.itemCode)) { flatTotalByItemCode.put(item.itemCode, item); }
                flatAmountByItemCode.put(item.itemCode, (flatAmountByItemCode.containsKey(item.itemCode) ? flatAmountByItemCode.get(item.itemCode) : 0) + amount);
            }

            List<String> flatItemCodes = new List<String>(flatTotalByItemCode.keySet());
            flatItemCodes.sort();

            // Tutte le occorrenze tranne gli strumenti che non prevedono DC.
            List<CostiStrumento> flatTargetSlots = new List<CostiStrumento>();
            for (CostiStrumento slot : slots) {
                if (!STRUMENTI_SENZA_DC.contains(slot.idStrumento)) { flatTargetSlots.add(slot); }
            }

            if (!flatTargetSlots.isEmpty()) {
                DettaglioCosto firstSlotCostiDc = flatTargetSlots.get(0).costiDc;
                for (String itemCode : flatItemCodes) {
                    PricingPaymentItem representativeItem = flatTotalByItemCode.get(itemCode);
                    addPaymentItemToDettaglioCosto(firstSlotCostiDc, representativeItem, flatAmountByItemCode.get(itemCode), oi, false, false);
                }

                for (Integer slotIndex = 1; slotIndex < flatTargetSlots.size(); slotIndex++) {
                    addZeroPlaceholderVociCosto(flatTargetSlots.get(slotIndex).costiDc, flatTotalByItemCode.values(), oi, false, false);
                }
            }
        }

        // Strumenti senza alcuna voce DC (ne' reale ne' a importo 0): costiDc non veicolato.
        for (CostiStrumento slot : slots) {
            if (slot.costiDc != null && slot.costiDc.vociCosto.isEmpty()) { slot.costiDc = null; }
        }

        if (fallbackInstrumentIdApplied > 0) { buildResult.assumptions.add('tariffa.costiStrumenti[]: fallback instrumentId applicato a ' + String.valueOf(fallbackInstrumentIdApplied) + ' PaymentItem DDA/DC senza instrumentId. Fallback risolto tramite attributi OrderItem + Custom Setting SIAE_StrumentoPriority__c + SIAE_RegolaVoceIncassoAttributo__c.' ); }

        if (ddaMapped == 0) { buildResult.warnings.add('tariffa.costiStrumenti[].costiDda: nessun PaymentItem DDA valido con instrumentId trovato o risolto da fallback.'); }
        if (dirittiConnessiPrevisti && dcMapped == 0) { addMissingParameter(buildResult, 'tariffa.costiStrumenti[].costiDc: nessun PaymentItem DC valido con instrumentId trovato o risolto da fallback.'); }

        List<CostiStrumento> result = buildCostiStrumentiResult(slots);

        if (!result.isEmpty()) { buildResult.assumptions.add('tariffa.costiStrumenti[] valorizzato con un elemento per ogni occorrenza di scheda.strumenti[]. ' + 'PaymentItem DDA/DC non FLAT raggruppati per instrumentId, abbinati per attributeCode quando possibile, altrimenti importo reale sull\'ultima occorrenza dello stesso idStrumento; ' + 'PaymentItem DC FLAT aggregati per itemCode con importo reale sulla prima occorrenza di scheda.strumenti[]. ' + 'Le occorrenze non rappresentative ricevono le stesse vociCosto a importo 0, cosi\' da avere sempre costiDda e costiDc valorizzati.' ); }
        if (!dirittiConnessiPrevisti) { buildResult.assumptions.add('tariffa.costiStrumenti[].costiDc non valorizzato: OrderItem.SIAE_DirittiConnessi__c non valorizzato o pari a 0 (licenza senza diritti connessi); eventuali PaymentItem DC vengono ignorati.'); }

        return result;
    }

    /**
     * Prova ad abbinare ogni PaymentItem alla occorrenza di scheda.strumenti[]
     * (indice di slot) generata dallo stesso attributo, quando piu' occorrenze
     * condividono lo stesso idStrumento (es. "Fino a 40"/"Maggiore di 40"
     * pollici). Restituisce null quando l'abbinamento non e' univocamente
     * determinabile (PaymentItem senza attributeCode - dato storico -, slot
     * senza attributeCodes noti, o un item che non matcha esattamente uno
     * slot): in quel caso il chiamante ricade sul comportamento precedente
     * (tutto sull'ultima occorrenza).
     */
    private static Map<Integer, List<PricingPaymentItem>> matchItemsToSlotsByAttributeCode(
        List<PricingPaymentItem> items,
        List<Integer> instrumentSlotIndexes,
        SalvaSchedaBuildResult buildResult
    ) {
        if (instrumentSlotIndexes == null || instrumentSlotIndexes.size() <= 1) { return null; }
        if (buildResult == null || buildResult.strumentiAttributeCodes == null) { return null; }

        Map<Integer, Set<String>> attributeCodesBySlotIndex = new Map<Integer, Set<String>>();
        for (Integer slotIndex : instrumentSlotIndexes) {
            if (slotIndex >= buildResult.strumentiAttributeCodes.size()) { return null; }
            Set<String> codes = buildResult.strumentiAttributeCodes.get(slotIndex);
            if (codes == null || codes.isEmpty()) { return null; }
            attributeCodesBySlotIndex.put(slotIndex, codes);
        }

        Map<Integer, List<PricingPaymentItem>> result = new Map<Integer, List<PricingPaymentItem>>();
        for (Integer slotIndex : instrumentSlotIndexes) { result.put(slotIndex, new List<PricingPaymentItem>()); }

        for (PricingPaymentItem item : items) {
            if (item == null || String.isBlank(item.attributeCode)) { return null; }

            String trimmedCode = item.attributeCode.trim();
            Integer matchedSlotIndex = null;

            for (Integer slotIndex : instrumentSlotIndexes) {
                if (attributeCodesBySlotIndex.get(slotIndex).contains(trimmedCode)) {
                    if (matchedSlotIndex != null) { return null; }
                    matchedSlotIndex = slotIndex;
                }
            }

            if (matchedSlotIndex == null) { return null; }

            result.get(matchedSlotIndex).add(item);
        }

        return result;
    }

    private static DettaglioCosto initializeDettaglioCosto() {
        DettaglioCosto dettaglio = new DettaglioCosto();
        dettaglio.tipoPagamento = DEFAULT_TIPO_PAGAMENTO_APPARECCHIO;
        //dettaglio.costoBase = 0;
        dettaglio.riduzioni = new List<Riduzione>();
        dettaglio.vociCosto = new List<VoceCosto>();
        return dettaglio;
    }

    private static void addPaymentItemToDettaglioCosto(
        DettaglioCosto dettaglio,
        PricingPaymentItem item,
        Decimal amount,
        OrderItem oi,
        Boolean isDda,
        Boolean negoziApparecchioOverride
    ) {
        if (dettaglio == null || item == null || amount == null) { return; }

        if (String.isBlank(dettaglio.idTabella)) { dettaglio.idTabella = resolveDettaglioIdTabella(oi, isDda); }

        /*
         * UAT Negozi: sotto i 200 mq di area vendita, le voci DC calcolate a
         * monte come FLAT (importo già corretto) vanno esposte come
         * tipoPagamento Apparecchio / tipo LC, non FLAT. L'importo non cambia.
         */
        Boolean applyNegoziOverride = negoziApparecchioOverride == true && !isDda && isFlatPaymentItem(item);

        if (isFlatPaymentItem(item) && !applyNegoziOverride) { dettaglio.tipoPagamento = TIPO_PAGAMENTO_FLAT; }

        //dettaglio.costoBase = (dettaglio.costoBase == null ? 0 : dettaglio.costoBase) + amount;

        if (dettaglio.riduzioni == null) { dettaglio.riduzioni = new List<Riduzione>(); }
        if (dettaglio.vociCosto == null) { dettaglio.vociCosto = new List<VoceCosto>(); }

        VoceCosto voceCosto = new VoceCosto();
        voceCosto.id = item.itemCode;
        voceCosto.tipo = applyNegoziOverride ? NEGOZI_REVENUE_ITEM_TYPE_APPARECCHIO_OVERRIDE : item.revenueItemType;
        voceCosto.importo = amount;
        voceCosto.genereCosto = resolveGenereCostoFromPaymentItemType(item.type);
        voceCosto.riduzioni = new List<Riduzione>();

        dettaglio.vociCosto.add(voceCosto);
    }

    /**
     * Risolve DettaglioCosto.idTabella per costiDda/costiDc a partire dai campi
     * Product2 dedicati, scegliendo in base a:
     * - ramo DDA/DC (isDda): determinato dal PaymentItem.type, non da Order.SIAE_IncludeDC__c;
     * - stato flat: OrderItem.SIAE_TypeOfFlatRate__c (non-flat / FLAT_AUDIO / FLAT_AUDIO_VIDEO).
     *
     * Mapping:
     * - non flat -> Product2.SIAE_IdTableDDA__c / SIAE_IdTableDC__c
     * - flat     -> Product2.SIAE_IdTableDDAFlat__c / SIAE_IdTableDCFlat__c
     *
     * Il campo *Flat__c puo' contenere:
     * - un singolo valore (la maggior parte dei prodotti: stesso idTabella per
     *   qualunque flat);
     * - due valori separati da ';' nella forma "valoreFlatAudio;valoreFlatAudioVideo"
     *   per i prodotti la cui tariffa flat dipende dai dispositivi audio/video
     *   (es. Bar: DDA "2a-AUDIO;2a-VIDEO", DC "SCF-PE-FA;SCF-PE-FV").
     *   In tal caso FLAT_AUDIO -> indice 0, FLAT_AUDIO_VIDEO -> indice 1.
     */
    private static String resolveDettaglioIdTabella(OrderItem oi, Boolean isDda) {
        if (oi == null || oi.Product2 == null) { return null; }

        String flatType = asString(oi.get('SIAE_TypeOfFlatRate__c'));

        if (!SIAE_UTIL_PricingMdA.isFlatRateSelected(flatType)) {
            return asString(isDda ? oi.Product2.get('SIAE_IdTableDDA__c') : oi.Product2.get('SIAE_IdTableDC__c'));
        }

        String rawFlat = asString(isDda ? oi.Product2.get('SIAE_IdTableDDAFlat__c') : oi.Product2.get('SIAE_IdTableDCFlat__c'));
        if (String.isBlank(rawFlat)) { return null; }

        List<String> flatValues = rawFlat.split(';');
        Boolean isAudioVideo = 'FLAT_AUDIO_VIDEO'.equalsIgnoreCase(flatType.trim());

        String selected = (isAudioVideo && flatValues.size() >= 2) ? flatValues[1] : flatValues[0];
        return String.isBlank(selected) ? null : selected.trim();
    }

    private static List<CostiStrumento> buildCostiStrumentiResult(
        List<CostiStrumento> slots
    ) {
        List<CostiStrumento> result = new List<CostiStrumento>();

        if (slots == null || slots.isEmpty()) { return result; }

        for (CostiStrumento costo : slots) {
            if (costo == null || String.isBlank(costo.idStrumento)) { continue; }

            Boolean hasDda = costo.costiDda != null &&
                costo.costiDda.vociCosto != null &&
                !costo.costiDda.vociCosto.isEmpty();

            Boolean hasDc = costo.costiDc != null &&
                costo.costiDc.vociCosto != null &&
                !costo.costiDc.vociCosto.isEmpty();

            if (hasDda || hasDc) { result.add(costo); }
        }

        return result;
    }

    /**
     * Aggiunge a un DettaglioCosto le vociCosto (per itemCode distinto) degli
     * item indicati, con importo forzato a 0. Usato per le occorrenze di
     * strumento non rappresentative, che devono comunque mostrare la voce
     * nello specchietto di dettaglio.
     */
    private static void addZeroPlaceholderVociCosto(
        DettaglioCosto dettaglio,
        List<PricingPaymentItem> items,
        OrderItem oi,
        Boolean isDda,
        Boolean negoziApparecchioOverride
    ) {
        if (dettaglio == null || items == null || items.isEmpty()) { return; }

        Set<String> itemCodesAlreadyAdded = new Set<String>();

        for (PricingPaymentItem item : items) {
            if (item == null || String.isBlank(item.itemCode) || itemCodesAlreadyAdded.contains(item.itemCode)) { continue; }

            itemCodesAlreadyAdded.add(item.itemCode);
            addPaymentItemToDettaglioCosto(dettaglio, item, 0, oi, isDda, negoziApparecchioOverride);
        }
    }

    private static String resolveFallbackInstrumentIdForCostiStrumenti(
        OrderItem oi,
        SalvaSchedaBuildResult buildResult
    ) {
        Set<String> availableAttributeCodes = loadAvailableOrderItemAttributeCodesForInstrumentFallback(
            oi,
            buildResult
        );

        if (availableAttributeCodes.isEmpty()) {
            buildResult.warnings.add(
                'tariffa.costiStrumenti[] fallback instrumentId: nessun attributo valorizzato trovato sull’OrderItem.'
            );
            return null;
        }

        List<InstrumentPriorityRow> priorityRows = getInstrumentPriorityRows();

        if (priorityRows.isEmpty()) {
            buildResult.warnings.add(
                'tariffa.costiStrumenti[] fallback instrumentId: nessun record trovato nel Custom Setting SIAE_StrumentoPriority__c.'
            );
            return null;
        }

        List<String> prioritizedAttributeCodes = new List<String>();
        Set<String> prioritizedAttributeCodeSet = new Set<String>();

        for (InstrumentPriorityRow priorityRow : priorityRows) {
            if (priorityRow == null || String.isBlank(priorityRow.attributeCode)) { continue; }

            String normalizedAttributeCode = normalizeKey(priorityRow.attributeCode);

            if (!availableAttributeCodes.contains(normalizedAttributeCode)) { continue; }

            if (prioritizedAttributeCodeSet.contains(normalizedAttributeCode)) { continue; }

            prioritizedAttributeCodes.add(priorityRow.attributeCode.trim());
            prioritizedAttributeCodeSet.add(normalizedAttributeCode);
        }

        if (prioritizedAttributeCodes.isEmpty()) { buildResult.warnings.add( 'tariffa.costiStrumenti[] fallback instrumentId: nessun attributo valorizzato sull’OrderItem matcha i record del Custom Setting SIAE_StrumentoPriority__c.'); return null;}

        Map<String, String> instrumentIdByAttributeCode = loadInstrumentIdByPriorityAttributeCode( prioritizedAttributeCodes, buildResult);

        for (String attributeCode : prioritizedAttributeCodes) {
            String normalizedAttributeCode = normalizeKey(attributeCode);

            if (instrumentIdByAttributeCode.containsKey(normalizedAttributeCode)) {
                String instrumentId = instrumentIdByAttributeCode.get(normalizedAttributeCode);

                buildResult.assumptions.add( 'tariffa.costiStrumenti[] fallback instrumentId risolto con attributo prioritario ' + attributeCode + ' -> idStrumento ' + instrumentId + '.'  );

                return instrumentId;
            }
        }

        buildResult.warnings.add(  'tariffa.costiStrumenti[] fallback instrumentId: gli attributi prioritari presenti sull’OrderItem non hanno una SIAE_RegolaVoceIncassoAttributo__c attiva con SIAE_IdInstrument__c valorizzato.' );
        return null;
    }

    private static Set<String> loadAvailableOrderItemAttributeCodesForInstrumentFallback(
        OrderItem oi,
        SalvaSchedaBuildResult buildResult
    ) {
        Set<String> result = new Set<String>();

        if (oi == null || oi.Id == null) { return result; }

        String valueFieldName = resolveOrderItemAttributeValueFieldName();
        if (String.isBlank(valueFieldName)) { buildResult.warnings.add( 'tariffa.costiStrumenti[] fallback instrumentId: impossibile individuare il campo valore su OrderItemAttribute.' ); return result; }

        Map<String, String> attributeValueByCode = loadOrderItemAttributeValueByCode(
            oi.Id,
            valueFieldName,
            buildResult,
            'tariffa.costiStrumenti[] fallback instrumentId'
        );

        for (String attributeCode : attributeValueByCode.keySet()) {
            String value = attributeValueByCode.get(attributeCode);

            if (isAvailableOrderItemAttributeValue(value)) { result.add(normalizeKey(attributeCode)); }
        }

        return result;
    }

    private static Boolean isAvailableOrderItemAttributeValue(String rawValue) {
        if (String.isBlank(rawValue)) { return false; }

        Decimal decimalValue = parseDecimalOrNull(rawValue);

        if (decimalValue != null) { return decimalValue != 0; }

        return true;
    }

    /**
     * Risolve AttributeCode -> idStrumento leggendo SIAE_RegolaVoceIncassoAttributo__c.
     *
     * La query viene eseguita solo per gli attributi non ancora presenti nella
     * cache transazionale, così più OrderItem con stessi attributi non ripetono
     * la stessa interrogazione.
     */
    private static Map<String, String> loadInstrumentIdByPriorityAttributeCode(
        List<String> prioritizedAttributeCodes,
        SalvaSchedaBuildResult buildResult
    ) {
        Map<String, String> result = new Map<String, String>();

        if (prioritizedAttributeCodes == null || prioritizedAttributeCodes.isEmpty()) { return result; }

        Set<String> attributeCodesToQuery = new Set<String>();
        Set<String> normalizedRequestedCodes = new Set<String>();

        for (String attributeCode : prioritizedAttributeCodes) {
            if (String.isBlank(attributeCode)) { continue; }

            String normalizedCode = normalizeKey(attributeCode);
            normalizedRequestedCodes.add(normalizedCode);

            if (!instrumentIdLookupLoadedAttributeCodes.contains(normalizedCode)) { attributeCodesToQuery.add(attributeCode.trim()); }
        }

        if (!attributeCodesToQuery.isEmpty()) {
            List<SIAE_RegolaVoceIncassoAttributo__c> ruleItems = [
                SELECT Id,
                       Name,
                       SIAE_AttributeCode__c,
                       SIAE_AttributeDefinition__c,
                       SIAE_AttributeDefinition__r.Code,
                       SIAE_IdInstrument__c,
                       SIAE_Active__c,
                       CreatedDate
                FROM SIAE_RegolaVoceIncassoAttributo__c
                WHERE SIAE_Active__c = true
                AND SIAE_IdInstrument__c != null
                AND (
                    SIAE_AttributeCode__c IN :attributeCodesToQuery
                    OR SIAE_AttributeDefinition__r.Code IN :attributeCodesToQuery
                )
                ORDER BY CreatedDate ASC
            ];

            for (SIAE_RegolaVoceIncassoAttributo__c ruleItem : ruleItems) {
                if (ruleItem == null || String.isBlank(ruleItem.SIAE_IdInstrument__c)) { continue; }

                String directAttributeCode = normalizeKey(ruleItem.SIAE_AttributeCode__c);
                if (String.isNotBlank(directAttributeCode) && !instrumentIdByAttributeCodeCache.containsKey(directAttributeCode)) { instrumentIdByAttributeCodeCache.put(directAttributeCode, ruleItem.SIAE_IdInstrument__c.trim()); }

                String attributeDefinitionCode = ruleItem.SIAE_AttributeDefinition__r == null
                    ? null
                    : ruleItem.SIAE_AttributeDefinition__r.Code;

                attributeDefinitionCode = normalizeKey(attributeDefinitionCode);
                if (String.isNotBlank(attributeDefinitionCode) && !instrumentIdByAttributeCodeCache.containsKey(attributeDefinitionCode)) { instrumentIdByAttributeCodeCache.put(attributeDefinitionCode, ruleItem.SIAE_IdInstrument__c.trim()); }
            }

            for (String queriedCode : attributeCodesToQuery) {
                instrumentIdLookupLoadedAttributeCodes.add(normalizeKey(queriedCode));
            }
        }

        for (String normalizedCode : normalizedRequestedCodes) {
            if (instrumentIdByAttributeCodeCache.containsKey(normalizedCode)) { result.put(normalizedCode,instrumentIdByAttributeCodeCache.get(normalizedCode)); }
        }

        return result;
    }

    /**
     * Costruisce tariffa.vociCosto[] appiattendo tariffa.costiStrumenti[]
     * (costiDda.vociCosto + costiDc.vociCosto di ogni elemento, nello stesso
     * ordine), invece di rileggere i PaymentItem grezzi. In questo modo
     * vociCosto[] eredita sia l'aggregazione per instrumentId sia i
     * placeholder a importo 0 già calcolati per costiStrumenti[], così come
     * atteso da SPORT.
     */
    private static List<VoceCosto> buildVociCostoFromCostiStrumenti(
        List<CostiStrumento> costiStrumenti,
        SalvaSchedaBuildResult buildResult
    ) {
        List<VoceCosto> result = new List<VoceCosto>();

        if (costiStrumenti == null || costiStrumenti.isEmpty()) {
            addMissingParameter(buildResult, 'tariffa.vociCosto[]: nessuna voce costo generata perché tariffa.costiStrumenti[] è vuoto.');
            return result;
        }

        for (CostiStrumento costo : costiStrumenti) {
            if (costo == null) { continue; }

            if (costo.costiDda != null && costo.costiDda.vociCosto != null) {
                result.addAll(costo.costiDda.vociCosto);
            }

            if (costo.costiDc != null && costo.costiDc.vociCosto != null) {
                result.addAll(costo.costiDc.vociCosto);
            }
        }

        if (result.isEmpty()) { addMissingParameter(buildResult,'tariffa.vociCosto[]: nessuna voce costo generata da tariffa.costiStrumenti[].' ); } else {
            buildResult.assumptions.add(
                'tariffa.vociCosto[] derivato appiattendo tariffa.costiStrumenti[].costiDda/costiDc.vociCosto, ' +
                'in modo coerente con lo spaccato per strumento (inclusi i placeholder a importo 0) atteso da SPORT.'
            );
        }

        return result;
    }


    private static List<VoceCosto> buildAltriCostiFromPaymentItems(
        OrderItem oi,
        SalvaSchedaBuildResult buildResult
    ) {
        List<VoceCosto> result = new List<VoceCosto>();

        if (oi == null || oi.Id == null) { buildResult.warnings.add('tariffa.altriCosti[]: impossibile leggere SIAE_PaymentItems__c perché OrderItem nullo.'); return result; }

        PricingPaymentItem.Wrapper paymentWrapper = getPaymentWrapperFromOrderItem(
            oi,
            buildResult,
            'tariffa.altriCosti[]',
            false
        );

        if (paymentWrapper == null || paymentWrapper.paymentItems == null || paymentWrapper.paymentItems.isEmpty()) { return result; }

        List<PricingPaymentItem> paymentItemsToAggregate =
            new List<PricingPaymentItem>();

        for (PricingPaymentItem item : paymentWrapper.paymentItems) {
            if (item == null) { continue; }

            if (!isAdditionalCostPaymentItem(item)) { continue; }

            if (String.isBlank(item.itemCode)) {
                buildResult.warnings.add(
                    'tariffa.altriCosti[]: PaymentItem ' + String.valueOf(item.type) +
                    ' ignorato perché itemCode non valorizzato.'
                );
                continue;
            }

            Decimal amount = parseDecimalOrNull(item.amount);
            if (amount == null) {
                buildResult.warnings.add(
                    'tariffa.altriCosti[]: PaymentItem ' + item.itemCode +
                    ' ignorato perché amount non numerico o non valorizzato: ' + String.valueOf(item.amount)
                );
                continue;
            }

            PricingPaymentItem normalized =
                new PricingPaymentItem();

            normalized.itemCode = item.itemCode;
            normalized.amount = item.amount;
            normalized.type = item.type;
            normalized.materialTaxClassification = item.materialTaxClassification;
            normalized.revenueItemType = item.revenueItemType;

            /*
             * Per tariffa.altriCosti[] serve aggregare la voce incasso QA,
             * non mantenere lo spaccato per strumento/paymentItems[].instrumentId.
             */
            normalized.instrumentId = null;

            paymentItemsToAggregate.add(normalized);
        }

        if (paymentItemsToAggregate.isEmpty()) {
            buildResult.warnings.add(
                'tariffa.altriCosti[]: nessun PaymentItem QA valido trovato in OrderItem.SIAE_PaymentItems__c.'
            );
            return result;
        }

        List<PricingPaymentItem> aggregatedPaymentItems =
            SIAE_UTIL_VoceIncassoEngine.deduplicate(paymentItemsToAggregate);

        for (PricingPaymentItem aggregatedItem : aggregatedPaymentItems) {
            if (aggregatedItem == null || String.isBlank(aggregatedItem.itemCode)) { continue; }

            Decimal aggregatedAmount = parseDecimalOrNull(aggregatedItem.amount);

            if (aggregatedAmount == null) {
                buildResult.warnings.add(
                    'tariffa.altriCosti[]: voce incasso ' + aggregatedItem.itemCode +
                    ' ignorata perché importo aggregato non numerico: ' + String.valueOf(aggregatedItem.amount)
                );
                continue;
            }

            VoceCosto altroCosto = new VoceCosto();
            altroCosto.id = aggregatedItem.itemCode;
            altroCosto.tipo = aggregatedItem.revenueItemType;
            altroCosto.importo = aggregatedAmount;
            altroCosto.genereCosto = resolveGenereCostoFromPaymentItemType(aggregatedItem.type);
            altroCosto.riduzioni = new List<Riduzione>();

            result.add(altroCosto);
        }

        if (result.isEmpty()) { buildResult.warnings.add('tariffa.altriCosti[]: nessun altro costo generato dai PaymentItem QA.' ); } else {
            buildResult.assumptions.add(
                'tariffa.altriCosti[] valorizzato da OrderItem.SIAE_PaymentItems__c considerando solo PaymentItem QA, ' +
                'aggregati tramite SIAE_UTIL_VoceIncassoEngine.deduplicate(...).'
            );
        }

        return result;
    }

    private static Boolean isRevenueCostPaymentItem(PricingPaymentItem item) {
        if (item == null || String.isBlank(item.type)) { return false; }

        String typeValue = item.type.trim();
        return typeValue.equalsIgnoreCase('DDA') || typeValue.equalsIgnoreCase('DC');
    }

    private static Boolean isFlatPaymentItem(PricingPaymentItem item) {
        return item != null &&
            String.isNotBlank(item.revenueItemType) &&
            item.revenueItemType.trim().equalsIgnoreCase(REVENUE_ITEM_TYPE_FLAT);
    }

    /**
     * UAT Negozi: sotto i 200 mq di area vendita ("SIAE-ATTR-QTA", metadata
     * SIAE_GenereLocaleParameter G06_LOCALE_mq_aree_vendita) le voci DC oggi
     * calcolate come FLAT vanno esposte come Apparecchio/LC in
     * tariffa.costiStrumenti[], senza cambiare l'importo già calcolato.
     * Risultato in cache per OrderItemId per evitare letture ripetute di
     * OrderItemAttribute nella stessa transazione.
     */
    private static Boolean isNegoziSottoSogliaMqAreeVendita(OrderItem oi, SalvaSchedaBuildResult buildResult) {
        if (oi == null || oi.Id == null || oi.Product2 == null ||
            oi.Product2.ProductCode != PRODUCT_CODE_NEGOZI) {
            return false;
        }

        if (negoziSottoSogliaMqAreeVenditaCache.containsKey(oi.Id)) {
            return negoziSottoSogliaMqAreeVenditaCache.get(oi.Id);
        }

        String valueFieldName = resolveOrderItemAttributeValueFieldName();
        Boolean sottoSoglia = false;

        if (String.isNotBlank(valueFieldName)) {
            Map<String, String> attributeValueByCode = loadOrderItemAttributeValueByCode(
                oi.Id,
                valueFieldName,
                buildResult,
                'tariffa.costiStrumenti[] (soglia mq Negozi)'
            );

            Decimal mqAreeVendita = parseDecimalOrNull(
                attributeValueByCode.get(normalizeKey(NEGOZI_MQ_AREE_VENDITA_ATTRIBUTE_CODE))
            );

            sottoSoglia = mqAreeVendita != null && mqAreeVendita < NEGOZI_MQ_AREE_VENDITA_SOGLIA_APPARECCHIO;
        }

        negoziSottoSogliaMqAreeVenditaCache.put(oi.Id, sottoSoglia);
        return sottoSoglia;
    }


    private static Boolean isAdditionalCostPaymentItem(PricingPaymentItem item) {
        if (item == null || String.isBlank(item.type)) { return false; }

        return item.type.trim().equalsIgnoreCase('QA');
    }

    private static String resolveGenereCostoFromPaymentItemType(String paymentItemType) {
        if (String.isBlank(paymentItemType)) { return null; }

        if (paymentItemType.trim().equalsIgnoreCase('DDA')) { return 'SM'; }

        if (paymentItemType.trim().equalsIgnoreCase('DC')) { return 'DC'; }

        if (paymentItemType.trim().equalsIgnoreCase('QA')) { return 'ACCORDO'; }

        return null;
    }

    private static void addMissingBusinessFields(SalvaSchedaBuildResult buildResult) {
        if (buildResult == null || buildResult.request == null || buildResult.request.scheda == null) { return; }

        SchedaData scheda = buildResult.request.scheda;

        if (scheda.dataInizio == null) addMissingParameter(buildResult, 'scheda.dataInizio');
        if (scheda.dataFine == null) addMissingParameter(buildResult, 'scheda.dataFine');
        if (String.isBlank(scheda.statoDda)) addMissingParameter(buildResult, 'scheda.statoDda');
        //if (String.isBlank(scheda.statoDc)) addMissingParameter(buildResult, 'scheda.statoDc');
        if (scheda.idCrmSpazio == null) addMissingParameter(buildResult, 'scheda.idCrmSpazio');
        if (scheda.idCrmOrganizzatore == null) addMissingParameter(buildResult, 'scheda.idCrmOrganizzatore');
        if (String.isBlank(scheda.idRiferimento)) addMissingParameter(buildResult, 'scheda.idRiferimento');
        if (String.isBlank(scheda.idCarrello)) addMissingParameter(buildResult, 'scheda.idCarrello');
        if (scheda.parametri == null) {
            scheda.parametri = new List<Parametro>();
            buildResult.assumptions.add(
                'scheda.parametri[] inizializzato a lista vuota. Lista vuota ammessa quando non ci sono parametri SCHEDA applicabili.'
            );
        }

        if (buildResult.request.tariffa == null) { addMissingParameter(buildResult, 'tariffa');  return; }

        TariffaData tariffa = buildResult.request.tariffa;

        if (String.isBlank(tariffa.idTabella)) addMissingParameter(buildResult, 'tariffa.idTabella');
        if (tariffa.dda == null) addMissingParameter(buildResult, 'tariffa.dda');
        if (tariffa.dc == null) addMissingParameter(buildResult, 'tariffa.dc');
        if (tariffa.quotaAccordo == null) addMissingParameter(buildResult, 'tariffa.quotaAccordo');
        if (tariffa.importoTotale == null) addMissingParameter(buildResult, 'tariffa.importoTotale');
        if (tariffa.vociCosto == null || tariffa.vociCosto.isEmpty()) addMissingParameter(buildResult, 'tariffa.vociCosto[]');

        if (tariffa.costiStrumenti == null || tariffa.costiStrumenti.isEmpty()) { addMissingParameter(buildResult,'tariffa.costiStrumenti[]'); } else {
            Boolean missingDdaIdTabella = false;
            Boolean missingDcIdTabella = false;

            for (CostiStrumento costo : tariffa.costiStrumenti) {
                if (costo == null || String.isBlank(costo.idStrumento)) { addMissingParameter(buildResult, 'tariffa.costiStrumenti[].idStrumento'); continue; }

                Boolean hasDdaDetail = costo.costiDda != null;
                Boolean hasDcDetail = costo.costiDc != null;

                if (!hasDdaDetail && !hasDcDetail) { addMissingParameter(buildResult, 'tariffa.costiStrumenti[].costiDda/costiDc'); continue; }

                if (hasDdaDetail) {
                    if (String.isBlank(costo.costiDda.idTabella)) { missingDdaIdTabella = true; }
                    if (String.isBlank(costo.costiDda.tipoPagamento)) { addMissingParameter(buildResult, 'tariffa.costiStrumenti[].costiDda.tipoPagamento'); }
                    //if (costo.costiDda.costoBase == null) { addMissingParameter(buildResult, 'tariffa.costiStrumenti[].costiDda.costoBase'); }
                    if (costo.costiDda.vociCosto == null || costo.costiDda.vociCosto.isEmpty()) { addMissingParameter(buildResult, 'tariffa.costiStrumenti[].costiDda.vociCosto[]'); }
                }

                if (hasDcDetail) {
                    if (String.isBlank(costo.costiDc.idTabella)) { missingDcIdTabella = true; }
                    if (String.isBlank(costo.costiDc.tipoPagamento)) { addMissingParameter(buildResult, 'tariffa.costiStrumenti[].costiDc.tipoPagamento'); }
                    //if (costo.costiDc.costoBase == null) { addMissingParameter(buildResult, 'tariffa.costiStrumenti[].costiDc.costoBase'); }
                    if (costo.costiDc.vociCosto == null || costo.costiDc.vociCosto.isEmpty()) { addMissingParameter(buildResult, 'tariffa.costiStrumenti[].costiDc.vociCosto[]');}
                }
            }

            if (missingDdaIdTabella) { addMissingParameter(buildResult,'tariffa.costiStrumenti[].costiDda.idTabella'); }
            if (missingDcIdTabella) { addMissingParameter(buildResult,'tariffa.costiStrumenti[].costiDc.idTabella'); }
        }

        buildResult.warnings.add(
            'tariffa.costiStrumenti[] viene popolato da PaymentItem DDA/DC non aggregati tramite instrumentId. I dettagli costiDda/costiDc sono creati solo se presenti PaymentItem validi per lo strumento.'
        );
    }

    // =========================================================================
    // CUSTOM METADATA ACCESSORS - NO SOQL
    // =========================================================================

    /*private static List<SIAE_GenereLocaleParameter__mdt> getSchedaParameterRows(
        String genereCode,
        SalvaSchedaBuildResult buildResult
    ) {
        Map<String, SIAE_GenereLocaleParameter__mdt> rowByParameterName =
            new Map<String, SIAE_GenereLocaleParameter__mdt>();

        List<SIAE_GenereLocaleParameter__mdt> fallbackRows = getGenereLocaleParametersSafely(
            GENERE_ALL,
            SCOPE_SCHEDA,
            buildResult
        );

        for (SIAE_GenereLocaleParameter__mdt row : fallbackRows) {
            if (isSchedaParameterRow(row)) { rowByParameterName.put(normalizeKey(row.SIAE_ParameterName__c),row); }
        }

        if (String.isNotBlank(genereCode)) {
            List<SIAE_GenereLocaleParameter__mdt> specificRows = getGenereLocaleParametersSafely(
                genereCode,
                SCOPE_SCHEDA,
                buildResult
            );

            for (SIAE_GenereLocaleParameter__mdt row : specificRows) {
                if (isSchedaParameterRow(row)) {  rowByParameterName.put(normalizeKey(row.SIAE_ParameterName__c), row); }
            }
        }

        List<SIAE_GenereLocaleParameter__mdt> result =
            new List<SIAE_GenereLocaleParameter__mdt>();

        List<String> keys = new List<String>(rowByParameterName.keySet());
        keys.sort();

        for (String key : keys) { result.add(rowByParameterName.get(key)); }

        return result;
    }*/
            
    private static List<SIAE_GenereLocaleParameter__mdt> getSchedaAndLocaleParameterRows(
        String genereCode,
        SalvaSchedaBuildResult buildResult
    ) {
        Map<String, SIAE_GenereLocaleParameter__mdt> rowByParameterName =
            new Map<String, SIAE_GenereLocaleParameter__mdt>();
    
        /*
         * Precedenza:
         * 1. ALL + LOCALE
         * 2. genere specifico + LOCALE
         * 3. ALL + SCHEDA
         * 4. genere specifico + SCHEDA
         *
         * In caso di stesso nome parametro, la riga caricata dopo sovrascrive
         * quella precedente. In questo modo manteniamo il fallback ALL ma diamo
         * precedenza al genere specifico e, a parità di nome, allo scope SCHEDA.
         */
        mergeParameterRowsByParameterName(
            rowByParameterName,
            getGenereLocaleParametersSafely(GENERE_ALL, SCOPE_LOCALE, buildResult),
            SCOPE_LOCALE,
            buildResult
        );
    
        if (String.isNotBlank(genereCode)) {
            mergeParameterRowsByParameterName(
                rowByParameterName,
                getGenereLocaleParametersSafely(genereCode, SCOPE_LOCALE, buildResult),
                SCOPE_LOCALE,
                buildResult
            );
        }
    
        mergeParameterRowsByParameterName(
            rowByParameterName,
            getGenereLocaleParametersSafely(GENERE_ALL, SCOPE_SCHEDA, buildResult),
            SCOPE_SCHEDA,
            buildResult
        );
    
        if (String.isNotBlank(genereCode)) {
            mergeParameterRowsByParameterName(
                rowByParameterName,
                getGenereLocaleParametersSafely(genereCode, SCOPE_SCHEDA, buildResult),
                SCOPE_SCHEDA,
                buildResult
            );
        }
    
        List<SIAE_GenereLocaleParameter__mdt> result =
            new List<SIAE_GenereLocaleParameter__mdt>();
    
        List<String> keys = new List<String>(rowByParameterName.keySet());
        keys.sort();
    
        for (String key : keys) {
            result.add(rowByParameterName.get(key));
        }
    
        return result;
    }
    
    private static void mergeParameterRowsByParameterName(
        Map<String, SIAE_GenereLocaleParameter__mdt> rowByParameterName,
        List<SIAE_GenereLocaleParameter__mdt> rows,
        String expectedScope,
        SalvaSchedaBuildResult buildResult
    ) {
        if (rowByParameterName == null || rows == null || rows.isEmpty()) {
            return;
        }
    
        for (SIAE_GenereLocaleParameter__mdt row : rows) {
            if (!isParameterRowForScope(row, expectedScope)) {
                continue;
            }
    
            if (String.isBlank(row.SIAE_ParameterName__c)) {
                if (buildResult != null) {
                    buildResult.warnings.add(
                        'Metadata ' + String.valueOf(expectedScope) + ' ' +
                        String.valueOf(row.DeveloperName) +
                        ': SIAE_ParameterName__c non valorizzato.'
                    );
                }
                continue;
            }
    
            rowByParameterName.put(
                normalizeKey(row.SIAE_ParameterName__c),
                row
            );
        }
    }
    
    private static Boolean isParameterRowForScope(
        SIAE_GenereLocaleParameter__mdt row,
        String expectedScope
    ) {
        return row != null &&
            String.isNotBlank(row.SIAE_ParameterName__c) &&
            String.isNotBlank(row.SIAE_Scope__c) &&
            row.SIAE_Scope__c.equalsIgnoreCase(expectedScope);
    }

    private static List<SIAE_GenereLocaleParameter__mdt> getGenereLocaleParametersSafely(
        String genereCode,
        String scope,
        SalvaSchedaBuildResult buildResult
    ) {
        try {
            return SIAE_UTIL_GenereLocaleConfig.getParameters(genereCode, scope);
        } catch (Exception ex) {
            if (buildResult != null) { buildResult.warnings.add('Errore lettura SIAE_GenereLocaleParameter__mdt tramite SIAE_UTIL_GenereLocaleConfig.getParameters(' + String.valueOf(genereCode) + ', ' + String.valueOf(scope) + '): ' + ex.getMessage() ); }
            return new List<SIAE_GenereLocaleParameter__mdt>();
        }
    }

    private static Boolean isSchedaParameterRow(SIAE_GenereLocaleParameter__mdt row) {
        return row != null && String.isNotBlank(row.SIAE_ParameterName__c) && String.isNotBlank(row.SIAE_Scope__c) &&  row.SIAE_Scope__c.equalsIgnoreCase(SCOPE_SCHEDA);
    }

    private static Map<String, String> getGenereCodeByGenereName() {
        if (genereCodeByGenereName == null) {
            genereCodeByGenereName = new Map<String, String>();
            for (SIAE_GenereLocale__mdt row : SIAE_GenereLocale__mdt.getAll().values()) {
                if (String.isNotBlank(row.SIAE_GenereName__c) && String.isNotBlank(row.SIAE_GenereCode__c)) {  genereCodeByGenereName.put(normalizeKey(row.SIAE_GenereName__c), row.SIAE_GenereCode__c.trim()); }
            }
        }
        return genereCodeByGenereName;
    }

    private static Map<String, List<SIAE_GenereLocaleParameter__mdt>> getStrumentoParameterIndexByKey() {
        if (strumentoParameterIndexByKey == null) {
            strumentoParameterIndexByKey = new Map<String, List<SIAE_GenereLocaleParameter__mdt>>();
            for (SIAE_GenereLocaleParameter__mdt row : SIAE_GenereLocaleParameter__mdt.getAll().values()) {
                if (!isStrumentoParameterRow(row)) { continue; }
                String key = buildParameterMetadataKey(row.SIAE_GenereCode__c, row.SIAE_Scope__c, row.SIAE_AttributeDefinitionCode__c);
                if (!strumentoParameterIndexByKey.containsKey(key)) { strumentoParameterIndexByKey.put(key, new List<SIAE_GenereLocaleParameter__mdt>()); }
                strumentoParameterIndexByKey.get(key).add(row);
            }
        }
        return strumentoParameterIndexByKey;
    }

    private static List<SIAE_GenereLocaleParameter__mdt> getStrumentoParameterRows(
        String genereCode,
        String attributeCode
    ) {
        Map<String, List<SIAE_GenereLocaleParameter__mdt>> indexByKey = getStrumentoParameterIndexByKey();
        List<SIAE_GenereLocaleParameter__mdt> result = new List<SIAE_GenereLocaleParameter__mdt>();

        String specificKey = buildParameterMetadataKey(genereCode, SCOPE_STRUMENTO, attributeCode);
        if (indexByKey.containsKey(specificKey)) {
            result.addAll(indexByKey.get(specificKey));
            return result;
        }

        String allKey = buildParameterMetadataKey(GENERE_ALL, SCOPE_STRUMENTO, attributeCode);
        if (indexByKey.containsKey(allKey)) { result.addAll(indexByKey.get(allKey)); }
        return result;
    }

    private static Boolean isStrumentoParameterRow(SIAE_GenereLocaleParameter__mdt row) {
        return row != null &&
            String.isNotBlank(row.SIAE_AttributeDefinitionCode__c) &&
            String.isNotBlank(row.SIAE_ParameterName__c) &&
            String.isNotBlank(row.SIAE_Scope__c) &&
            row.SIAE_Scope__c.equalsIgnoreCase(SCOPE_STRUMENTO);
    }

    private static String buildParameterMetadataKey(
        String genereCode,
        String scope,
        String attributeCode
    ) {
        return normalizeKey(String.isBlank(genereCode) ? GENERE_ALL : genereCode) +
            '|' + normalizeKey(scope) + '|' + normalizeKey(attributeCode);
    }

    // =========================================================================
    // RESPONSE MAPPING
    // =========================================================================

    /**
     * Prepara l'update dell'OrderItem a partire dalla response salvaScheda.
     *
     * Campi response:
     * - idSchedaDda -> OrderItem.SIAE_DDACardId__c
     * - idSchedaDc  -> OrderItem.SIAE_DCCardId__c
     *
     * idCarrello e idRiferimento vengono già inviati in request e non vengono
     * rimappati qui.
     */
    private static OrderItem buildOrderItemUpdateFromSalvaSchedaResponse(
        Id orderItemId,
        SalvaSchedaCalloutResult calloutResult
    ) {
        if (orderItemId == null || calloutResult == null || calloutResult.success != true || calloutResult.response == null) { return null; }

        OrderItem updateRow = new OrderItem(Id = orderItemId);
        Boolean hasChanges = false;

        hasChanges = putCardIdValue(
            updateRow,
            'SIAE_DDACardId__c',
            calloutResult.response.idSchedaDda
        ) || hasChanges;

        hasChanges = putCardIdValue(
            updateRow,
            'SIAE_DCCardId__c',
            calloutResult.response.idSchedaDc
        ) || hasChanges;

        return hasChanges ? updateRow : null;
    }

    /**
     * Scrive i card id sui campi Salesforce come testo.
     *
     * La response SPORT espone idSchedaDda/idSchedaDc come integer int64, quindi
     * nel DTO Apex rimangono Long. Solo nel momento dell'update verso i campi
     * OrderItem.SIAE_DDACardId__c e OrderItem.SIAE_DCCardId__c, che sono Text
     * External Id, il valore viene trasformato in String.
     */
    private static Boolean putCardIdValue(SObject target, String fieldName, Long value) {
        if (target == null || String.isBlank(fieldName) || value == null) { return false; }

        Map<String, Schema.SObjectField> fieldsByName =
            OrderItem.SObjectType.getDescribe().fields.getMap();

        if (!fieldsByName.containsKey(fieldName)) { return false; }

        target.put(fieldName, String.valueOf(value));
        return true;
    }

    /**
     * Parser tollerante per la response salvaScheda.
     *
     * Lo Swagger espone idSchedaDda/idSchedaDc come integer int64, quindi la
     * response Apex li mantiene come Long. La conversione a String viene fatta
     * solo nel mapping DML verso OrderItem, perché lato Salesforce i campi sono
     * Text External Id.
     */
    private static SalvaSchedaResponse parseSalvaSchedaResponse(String rawBody) {
        if (String.isBlank(rawBody)) { return null; }

        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(rawBody);

        SalvaSchedaResponse response = new SalvaSchedaResponse();
        response.idCarrello = asString(getPayloadValueIgnoreCase(payload, 'idCarrello'));
        response.idRiferimento = asString(getPayloadValueIgnoreCase(payload, 'idRiferimento'));
        response.idSchedaDda = parseResponseLongId(getPayloadValueIgnoreCase(payload, 'idSchedaDda'));
        response.idSchedaDc = parseResponseLongId(getPayloadValueIgnoreCase(payload, 'idSchedaDc'));
        return response;
    }

    /**
     * Converte il valore id della response in Long, coerentemente con lo Swagger
     * SPORT che dichiara idSchedaDda/idSchedaDc come integer int64.
     *
     * Rimane tollerante verso payload/mock che dovessero arrivare come stringa
     * numerica o come decimal intero, ma il tipo esposto nel DTO resta Long.
     */
    private static Long parseResponseLongId(Object rawValue) {
        if (rawValue == null) { return null; }

        String value = String.valueOf(rawValue).trim();
        if (String.isBlank(value)) { return null; }

        if (value.endsWith('.0')) { value = value.substring(0,value.length() - 2); }

        try {
            return Long.valueOf(value);
        } catch (Exception longEx) {
            try {
                Decimal decimalValue = Decimal.valueOf(value);
                return Long.valueOf(String.valueOf(decimalValue.setScale(0, RoundingMode.DOWN)));
            } catch (Exception decimalEx) {
                return null;
            }
        }
    }

    private static Object getPayloadValueIgnoreCase(Map<String, Object> payload, String key) {
        if (payload == null || String.isBlank(key)) { return null; }

        if (payload.containsKey(key)) { return payload.get(key); }

        for (String currentKey : payload.keySet()) {
            if (currentKey != null && currentKey.equalsIgnoreCase(key)) { return payload.get(currentKey); }
        }

        return null;
    }

    // =========================================================================
    // CALLOUT RESPONSE
    // =========================================================================

    private static SalvaSchedaCalloutResult parseResponse(HttpResponse res) {
        SalvaSchedaCalloutResult result = new SalvaSchedaCalloutResult();
        result.statusCode = res.getStatusCode();
        result.status = res.getStatus();
        result.rawBody = res.getBody();
        result.success = res.getStatusCode() >= 200 && res.getStatusCode() < 300;

        if (String.isBlank(result.rawBody)) { return result; }

        if (result.success) {
            try {
                result.response = parseSalvaSchedaResponse(result.rawBody);
            } catch (Exception ex) {
                result.parseError = ex.getMessage();
            }
        } else {
            try {
                result.error = (ErrorResponse) JSON.deserialize(result.rawBody, ErrorResponse.class);
            } catch (Exception ex) {
                result.error = new ErrorResponse();
                result.error.code = String.valueOf(result.statusCode);
                result.error.message = result.rawBody;
                result.parseError = ex.getMessage();
            }
        }
        return result;
    }

    private static void validateRequest(SalvaSchedaRequest requestBody) {
        if (requestBody == null) throw new SalvaSchedaException('Request salvaScheda obbligatoria.');
        if (requestBody.scheda == null) throw new SalvaSchedaException('Campo obbligatorio mancante: scheda.');
        if (requestBody.tariffa == null) throw new SalvaSchedaException('Campo obbligatorio mancante: tariffa.');
    }

    private static void validateHeaders(SalvaSchedaHeaders headers) {
        /*
         * Metodo lasciato solo per compatibilità interna legacy.
         * Gli header salvaScheda sono ora gli stessi della CreateLocale e vengono
         * costruiti da SIAE_UTIL_IntegrationConfig.buildHttpRequest(...):
         * - X-Correlation-ID
         * - X-Transaction-ID
         * - X-System-ID
         *
         * Non validiamo più transactionID/sourceSystem/token/userId/seprag.
         */
    }

    // =========================================================================
    // HELPERS
    // =========================================================================

    /**
     * Individua il campo runtime che contiene il valore dell’OrderItemAttribute.
     *
     * Il risultato viene messo in cache perché lo stesso campo viene usato da
     * scheda.parametri, scheda.strumenti e fallback instrumentId.
     */
    private static String resolveOrderItemAttributeValueFieldName() {
        if (orderItemAttributeValueFieldNameCache != null) { return orderItemAttributeValueFieldNameCache; }

        Schema.SObjectType objectType = Schema.getGlobalDescribe().get('OrderItemAttribute');
        if (objectType == null) { return null; }

        Map<String, Schema.SObjectField> fields = objectType.getDescribe().fields.getMap();
        List<String> candidates = new List<String>{
            'Value', 'Value__c', 'AttributeValue', 'AttributeValue__c',
            'TextValue', 'TextValue__c', 'NumberValue', 'NumberValue__c',
            'Quantity', 'Quantity__c'
        };

        for (String candidate : candidates) {
            if (fields.containsKey(candidate)) {
                orderItemAttributeValueFieldNameCache = candidate;
                return orderItemAttributeValueFieldNameCache;
            }
        }
        return null;
    }

    private static Boolean hasConfiguredEnumValue(SIAE_GenereLocaleParameter__mdt row) {
        return row != null && !splitSemicolonValues(row.SIAE_EnumValues__c).isEmpty();
    }

    private static String getFirstConfiguredEnumValue(SIAE_GenereLocaleParameter__mdt row) {
        List<String> values = splitSemicolonValues(row == null ? null : row.SIAE_EnumValues__c);
        return values.isEmpty() ? null : values[0];
    }

    private static Boolean isFixedParameter(SIAE_GenereLocaleParameter__mdt row) {
        if (row == null) return false;
        if (!String.valueOf(row.SIAE_DataType__c).equalsIgnoreCase(DATA_TYPE_ENUMERATION)) return false;
        return splitSemicolonValues(row.SIAE_EnumValues__c).size() == 1;
    }

    private static String getFixedParameterValue(SIAE_GenereLocaleParameter__mdt row) {
        List<String> values = splitSemicolonValues(row.SIAE_EnumValues__c);
        return values.isEmpty() ? null : values[0];
    }

    private static Boolean isStringParameter(SIAE_GenereLocaleParameter__mdt row) {
        return row != null &&
            String.isNotBlank(row.SIAE_DataType__c) &&
            row.SIAE_DataType__c.trim().equalsIgnoreCase(DATA_TYPE_STRING);
    }

    private static Boolean hasStringParameterRow(List<SIAE_GenereLocaleParameter__mdt> rows) {
        if (rows == null) { return false; }
        for (SIAE_GenereLocaleParameter__mdt row : rows) {
            if (isStringParameter(row)) { return true; }
        }
        return false;
    }

    private static String resolveStringParameterValue(
        SIAE_GenereLocaleParameter__mdt row,
        String rawValue,
        SalvaSchedaBuildResult buildResult,
        String attributeCode
    ) {
        String value = rawValue == null ? null : rawValue.trim();

        if (String.isBlank(value)) {
            return String.isNotBlank(row.SIAE_DefaultValue__c) ? row.SIAE_DefaultValue__c.trim() : null;
        }

        if (String.isBlank(row.SIAE_ValueMap__c)) { return value; }

        try {
            String mapped = SIAE_UTIL_GenereLocaleConfig.mapPicklistValue(row.SIAE_ValueMap__c, value, false);
            if (String.isNotBlank(mapped)) { return mapped; }

            if (buildResult != null) {
                buildResult.warnings.add(
                    'Attributo ' + attributeCode + ': valore "' + value +
                    '" non presente in SIAE_ValueMap__c del metadata ' + row.DeveloperName +
                    '. Inviato il valore originale.'
                );
            }
        } catch (Exception ex) {
            if (buildResult != null) {
                buildResult.warnings.add(
                    'Attributo ' + attributeCode + ': rimappatura SIAE_ValueMap__c fallita per il metadata ' +
                    row.DeveloperName + '. Dettaglio: ' + ex.getMessage() + '. Inviato il valore originale.'
                );
            }
        }

        return value;
    }

    private static List<String> splitSemicolonValues(String rawValues) {
        List<String> result = new List<String>();
        if (String.isBlank(rawValues)) return result;
        for (String item : rawValues.split(';')) {
            if (String.isNotBlank(item)) result.add(item.trim());
        }
        return result;
    }

    private static Object safeGet(SObject record, String fieldName) {
        if (record == null || String.isBlank(fieldName)) return null;
        try {
            return record.get(fieldName);
        } catch (Exception ex) {
            return null;
        }
    }

    private static String buildInstrumentGroupKey(String idStrumento, Map<String, String> fixedParams) {
        List<String> parts = new List<String>{ idStrumento };
        if (fixedParams != null && !fixedParams.isEmpty()) {
            List<String> fixedNames = new List<String>(fixedParams.keySet());
            fixedNames.sort();
            for (String fixedName : fixedNames) {
                parts.add(fixedName + '=' + fixedParams.get(fixedName));
            }
        }
        return String.join(parts, '|');
    }

    private static Decimal parseDecimalOrNull(String rawValue) {
        if (String.isBlank(rawValue)) return null;
        try {
            return Decimal.valueOf(rawValue.trim().replace(',', '.'));
        } catch (Exception ex) {
            return null;
        }
    }

    // PricingPaymentItem.amount è Object: TTPP lo serializza Decimal, MdA String formattata.
    private static Decimal parseDecimalOrNull(Object rawValue) {
        return rawValue == null ? null : parseDecimalOrNull(String.valueOf(rawValue));
    }

    /**
     * Ricostruisce il wrapper da SIAE_PaymentItems__c senza JSON.deserialize tipizzato:
     * PricingPaymentItem.amount è Object e il deserializer Apex non supporta campi Object.
     * L'importo resta String, come nel formato persistito dal PostHook MdA.
     */
    @TestVisible
    private static PricingPaymentItem.Wrapper parsePaymentWrapper(String rawPaymentItems) {
        Object root = JSON.deserializeUntyped(rawPaymentItems);
        if (root == null) return null;

        PricingPaymentItem.Wrapper wrapper = new PricingPaymentItem.Wrapper();
        Object rawItems = ((Map<String, Object>) root).get('paymentItems');
        if (rawItems == null) {
            wrapper.paymentItems = null;
            return wrapper;
        }
        for (Object rawItem : (List<Object>) rawItems) {
            Map<String, Object> itemMap = (Map<String, Object>) rawItem;
            if (itemMap == null) {
                wrapper.paymentItems.add(null);
                continue;
            }
            PricingPaymentItem item = new PricingPaymentItem();
            item.itemCode = asString(itemMap.get('itemCode'));
            item.amount = asString(itemMap.get('amount'));
            item.type = asString(itemMap.get('type'));
            item.eventGenre = asString(itemMap.get('eventGenre'));
            item.incidencePercentage = parseDecimalOrNull(itemMap.get('incidencePercentage'));
            item.materialTaxClassification = asString(itemMap.get('materialTaxClassification'));
            item.revenueItemType = asString(itemMap.get('revenueItemType'));
            item.instrumentId = asString(itemMap.get('instrumentId'));
            item.attributeCode = asString(itemMap.get('attributeCode'));
            wrapper.paymentItems.add(item);
        }
        return wrapper;
    }

    /**
     * SPORT richiede le percentuali di sconto accordo (DC/DDA) come numero
     * intero (es. 60 per "60%"), mentre internamente SIAE_DCDiscountPercent__c
     * e SIAE_DDADiscountPercent__c vengono valorizzati dal Pricing PostHook come
     * frazione 0-1 (es. 0.60), la stessa scala usata per i calcoli di sconto.
     * La conversione avviene solo qui, al momento dell'invio: i campi sorgente
     * e i calcoli di pricing restano invariati.
     */
    private static Decimal fractionToIntegerPercent(Decimal fractionValue) {
        if (fractionValue == null) return 0;
        return (fractionValue * 100).setScale(0, RoundingMode.HALF_UP);
    }

    private static Long parseLongOrNull(Object rawValue) {
        if (rawValue == null) return null;
        String value = String.valueOf(rawValue).trim();
        if (String.isBlank(value)) return null;
        try {
            Decimal decimalValue = Decimal.valueOf(value.replace(',', '.'));
            return decimalValue.longValue();
        } catch (Exception ex) { return null; }
    }

    private static String formatQuantity(Decimal value) {
        if (value == null) return '0';
        Decimal rounded = value.setScale(0);
        if (value == rounded) return String.valueOf(rounded);

        String formatted = String.valueOf(value);
        while (formatted.contains('.') && formatted.endsWith('0')) { formatted = formatted.substring(0, formatted.length() - 1); }
        if (formatted.endsWith('.')) { formatted = formatted.substring(0,formatted.length() - 1); }
        return formatted;
    }

    /**
     * Normalizza il valore di uno scheda.parametri: se è un numero intero
     * (es. "10.0") viene serializzato senza decimali ("10"), mentre valori non
     * numerici (codici enum, "NO", "SPORT") o con decimali reali ("10.5")
     * restano invariati. Gli importi tariffari non passano da qui: restano double.
     */
    private static String normalizeIntegerParametroValue(String value) {
        if (String.isBlank(value)) { return value; }

        Decimal parsed = parseDecimalOrNull(value.trim());
        if (parsed == null) { return value; }
        if (parsed != parsed.setScale(0)) { return value; }

        return String.valueOf(parsed.setScale(0));
    }

    private static String normalizeKey(String value) {
        return String.isBlank(value) ? '' : value.trim().toUpperCase();
    }

    private static String asString(Object value) {
        return value == null || String.valueOf(value) == '0.0' ? null : String.valueOf(value);
    }

    private static void addMissingParameter(SalvaSchedaBuildResult buildResult, String message) {
        if (buildResult == null || String.isBlank(message)) return;
        if (!buildResult.missingParameters.contains(message)) { buildResult.missingParameters.add(message); }
    }

    /**
     * Aggiunge un messaggio come missing parameter o warning in base al contesto.
     */
    private static void addBuildMessage(
        SalvaSchedaBuildResult buildResult,
        String message,
        Boolean asMissingParameter
    ) {
        if (buildResult == null || String.isBlank(message)) { return; }

        if (asMissingParameter == true) { addMissingParameter(buildResult,message); } else if (!buildResult.warnings.contains(message)) {
            buildResult.warnings.add(message);
        }
    }

    // =========================================================================
    // LOGGING HELPERS
    // =========================================================================

    private class DeferredRequestResponseLog {
        public String correlationId;
        public String endpoint;
        public String method;
        public String recordId;
        public String requestBody;
        public String responseBody;
        public Integer statusCode;
        public String serviceName;
    }

    private static void addOrWriteRequestResponseLog(
        List<DeferredRequestResponseLog> deferredLogs,
        String correlationId,
        String endpoint,
        String method,
        String recordId,
        String requestBody,
        String responseBody,
        Integer statusCode
    ) {
        if (deferredLogs != null) {
            DeferredRequestResponseLog logEntry = new DeferredRequestResponseLog();
            logEntry.correlationId = correlationId;
            logEntry.endpoint = endpoint;
            logEntry.method = method;
            logEntry.recordId = recordId;
            logEntry.requestBody = requestBody;
            logEntry.responseBody = JSON.serialize(responseBody, true);
            logEntry.statusCode = statusCode;
            logEntry.serviceName = LOG_SERVICE_NAME;
            deferredLogs.add(logEntry);
            return;
        }

        safeLogRequestResponse(
            correlationId,
            endpoint,
            method,
            recordId,
            requestBody,
            JSON.serialize(responseBody, true),
            statusCode,
            LOG_SERVICE_NAME
        );
    }

    private static void flushRequestResponseLogs(List<DeferredRequestResponseLog> deferredLogs) {
        if (deferredLogs == null || deferredLogs.isEmpty()) { return; }

        for (DeferredRequestResponseLog logEntry : deferredLogs) {
            if (logEntry == null) { continue; }

            safeLogRequestResponse(
                logEntry.correlationId,
                logEntry.endpoint,
                logEntry.method,
                logEntry.recordId,
                logEntry.requestBody,
                logEntry.responseBody,
                logEntry.statusCode,
                logEntry.serviceName
            );
        }
    }

    private static void safeLogRequestResponse(
        String correlationId,
        String endpoint,
        String method,
        String recordId,
        String requestBody,
        String responseBody,
        Integer statusCode,
        String serviceName
    ) {
        if (Test.isRunningTest()) { return; }

        try {
            SIAE_UTIL_Log.logRequestResponse(
                correlationId,
                endpoint,
                method,
                recordId,
                requestBody,
                responseBody,
                statusCode,
                serviceName
            );
        } catch (Exception logEx) {
            System.debug(
                LoggingLevel.WARN,
                'Errore scrittura log request/response ' + serviceName + ': ' + logEx.getMessage()
            );
        }
    }

    private static void safeLogException(
        Exception ex,
        String correlationId,
        Id recordId,
        String serviceName
    ) {
        if (Test.isRunningTest()) { return; }

        try {
            SIAE_UTIL_Log.logException(
                ex,
                correlationId,
                recordId == null ? null : String.valueOf(recordId),
                serviceName
            );
        } catch (Exception logEx) {
            System.debug(
                LoggingLevel.WARN,
                'Errore scrittura log eccezione ' + serviceName + ': ' + logEx.getMessage()
            );
        }
    }

    // =========================================================================
    // INTERNAL ACCUMULATOR
    // =========================================================================

    /**
     * Wrapper ordinabile per il Custom Setting SIAE_InstrumentPriority__c.
     *
     * Permette di usare getAll() senza SOQL e mantenere comunque l’ordinamento
     * per priorità crescente, poi per Name.
     */
    private class InstrumentPriorityRow implements Comparable {
        public String name;
        public String attributeCode;
        public Decimal priority;

        public Integer compareTo(Object otherObject) {
            InstrumentPriorityRow other = (InstrumentPriorityRow) otherObject;

            if (priority == null && other.priority != null) return 1;
            if (priority != null && other.priority == null) return -1;
            if (priority != null && other.priority != null) {
                if (priority < other.priority) return -1;
                if (priority > other.priority) return 1;
            }

            String currentName = name == null ? '' : name;
            String otherName = other.name == null ? '' : other.name;
            return currentName.compareTo(otherName);
        }
    }

    private class InstrumentAccumulator {
        public String idStrumento;
        public String nomeStrumento;
        public Map<String, Decimal> quantityParams = new Map<String, Decimal>();
        public Map<String, String> fixedParams = new Map<String, String>();
        public Map<String, String> textParams = new Map<String, String>();
        public Set<String> attributeCodes = new Set<String>();

        public void addAttributeCode(String attributeCode) {
            if (String.isBlank(attributeCode)) { return; }
            attributeCodes.add(attributeCode.trim());
        }

        public void addQuantityParametro(String nomeParametro, Decimal value) {
            if (String.isBlank(nomeParametro) || value == null) return;
            if (!quantityParams.containsKey(nomeParametro)) quantityParams.put(nomeParametro, 0);
            quantityParams.put(nomeParametro, quantityParams.get(nomeParametro) + value);
        }

        public void addFixedParametro(String nomeParametro, String value) {
            if (String.isBlank(nomeParametro) || String.isBlank(value)) return;
            fixedParams.put(nomeParametro, value);
        }

        public void addTextParametro(String nomeParametro, String value) {
            if (String.isBlank(nomeParametro) || String.isBlank(value)) return;
            textParams.put(nomeParametro, value);
        }
    }

    // =========================================================================
    // DTO BUILD RESULT
    // =========================================================================

    public class SalvaSchedaBuildResult {
        public SalvaSchedaRequest request;
        public Id orderItemId;
        public String resolvedGenereLocaleCode;
        public List<String> missingParameters = new List<String>();
        public List<String> warnings = new List<String>();
        public List<String> assumptions = new List<String>();

        /*
         * Attributi (es. SIAE-ATTR-TVOVER40/TVUNDER40) che hanno generato ogni
         * occorrenza di scheda.strumenti[], stesso ordine/indice della lista.
         * Usato da buildCostiStrumentiFromPaymentItems per abbinare i
         * PaymentItem.attributeCode alla giusta occorrenza quando piu'
         * occorrenze condividono lo stesso idStrumento.
         */
        public List<Set<String>> strumentiAttributeCodes = new List<Set<String>>();
    }

    // =========================================================================
    // HEADERS
    // =========================================================================

    public class SalvaSchedaHeaders {
        public String transactionID;
        public String sourceSystem;
        public String token;
        public String userId;
        public String seprag;
        public String authorization;
    }

    // =========================================================================
    // RESULT WRAPPER
    // =========================================================================

    public class SalvaSchedaCalloutResult {
        public Boolean success;
        public Integer statusCode;
        public String status;
        public String rawBody;
        public String parseError;
        public SalvaSchedaResponse response;
        public ErrorResponse error;
    }

    // =========================================================================
    // REQUEST ROOT
    // =========================================================================

    public class SalvaSchedaRequest {
        public SchedaData scheda;
        public TariffaData tariffa;
        public AccordoInfo accordo;
    }

    public class SchedaData {
        public String tipoSottoscrizione;
        public String tipoPeriodo;
        public Boolean flagMostra;
        public Date dataInizio;
        public Date dataFine;
        public String statoDda;
        public String statoDc;
        public Long idCrmSpazio;
        public Long idCrmOrganizzatore;
        public String idRiferimento;
        public String idCarrello;
        public List<Parametro> parametri;
        public List<Strumento> strumenti;
    }

    public class Strumento {
        public String idStrumento;
        public List<Parametro> parametri;
    }

    public class Parametro {
        public String nome;
        public String valore;
        public Parametro() {}
        public Parametro(String nome, String valore) {
            this.nome = nome;
            this.valore = valore;
        }
    }

    public class TariffaData {
        public String idTabella;
        public Decimal dda;
        public Decimal dc;
        public Decimal quotaAccordo;
        public Decimal importoTotale;
        public List<VoceCosto> vociCosto;
        public List<VoceCosto> altriCosti;
        public List<CostiStrumento> costiStrumenti;
    }

    public class CostiStrumento {
        public String idStrumento;
        public DettaglioCosto costiDda;
        public DettaglioCosto costiDc;
    }

    public class DettaglioCosto {
        public String idTabella;
        public String tipoPagamento;
        public Decimal costoBase;
        public List<Riduzione> riduzioni;
        public List<VoceCosto> vociCosto;
    }

    public class VoceCosto {
        public String id;
        public String tipo;
        public Decimal importo;
        public String genereCosto;
        public List<Riduzione> riduzioni;
    }

    public class Riduzione {
        public String tipo;
        public Decimal costoPre;
        public Decimal costoPos;
        public String percentualeSconto;
        public String descrizioneRegola;
        public String nomeRegola;
        public String dodicesimi;
    }

    public class AccordoInfo {
        public Decimal idCrmAccordo;
        public Decimal idCrmAssociazione;
        public String codiceAccordo;
        public Decimal percentualeScontoDc;
        public Decimal percentualeScontoDda;
    }

    public class SalvaSchedaResponse {
        public String idCarrello;
        public String idRiferimento;
        public Long idSchedaDda;
        public Long idSchedaDc;
    }

    public class ErrorResponse {
        public String code;
        public String message;
    }
}