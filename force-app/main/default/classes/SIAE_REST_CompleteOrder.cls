/**
 * @description      Provider DRO che invoca l'API Mulesoft `completa-ordine`
 *                   per completare/fatturare un ordine digital.
 * @author           Gaetano Iuliano - gaetano.iuliano@nttdata.com
 * @group            NTT Data — SIAE
 * @createdDate      2026-06-15
 * @lastModifiedDate 2026-06-15
 * @lastModifiedBy   Gaetano Iuliano
 */
global with sharing class SIAE_REST_CompleteOrder
        implements industriesintegrationfwk.ProcessIntegrationProviderAdvanced {

    private static final String CONFIG_NAME = 'CompleteOrder';

    private static final String NODE_ASYNC      = 'notificaMovimento_async';
    private static final String NODE_REQUEST    = 'requestDTO';
    private static final Integer HTTP_ACCEPTED   = 202;

    // ── DTO ─────────────────────────────────────────────────────────────────

    public class SalesforceCompleteOrderDTO {
        public String     orderId;
        public String     stepId;
        public List<Long> idSchede;
        public Long       idCrmOrganizzatore;
    }

    public class NotificaMovimentoAsyncDTO {
        public Object                      requestDTO;
        public SalesforceCompleteOrderDTO  salesforce;
    }

    public class CompleteOrderRequestDTO {
        public NotificaMovimentoAsyncDTO notificaMovimento_async;
    }

    public class CompleteOrderResponseDTO {
        public Long idPacchettoQuietanza;
    }

    public class CompleteOrderException extends Exception {}

    // ── Provider attributes ─────────────────────────────────────────────────

    global static List<industriesintegrationfwk.ApexProviderAttr> getProviderAttributes() {
        return SIAE_UTIL_IntegrationConfig.buildProviderAttributes(CONFIG_NAME);
    }

    // ── Callout ─────────────────────────────────────────────────────────────

    global static industriesintegrationfwk.IntegrationCalloutResponse executeCallout(
        String requestGuid,
        String inputRecordId,
        String payload,
        Map<String, Object> attributes,
        industriesintegrationfwk.HttpBaseProvider httpProvider
    ) {
        Id orderId;
        String correlationId;
        Id orderItemId;
        try {
            if (String.isBlank(inputRecordId)) {
                throw new IllegalArgumentException('inputRecordId is required.');
            }
            orderItemId = (Id) inputRecordId;
            if (orderItemId.getSObjectType() != OrderItem.SObjectType) {
                throw new IllegalArgumentException('inputRecordId must be an Order Item ID.');
            }
            
            List<OrderItem> listOfOrderItem = new List<OrderItem>([SELECT Id, OrderId FROM OrderItem WHERE Id =: orderItemId]);
            if(listOfOrderItem.isEmpty()){
                throw new IllegalArgumentException('No Order Item found.');
            }
            orderId = listOfOrderItem[0].OrderId;
            String configName = SIAE_UTIL_IntegrationConfig.resolveConfigName(attributes, CONFIG_NAME);

            Order ord = loadOrder(orderId);

            CompleteOrderRequestDTO requestDTO = buildRequest(ord, requestGuid);
            String requestBody = JSON.serialize(requestDTO, true);

            correlationId = UUID.randomUUID().toString();
            HttpRequest req = SIAE_UTIL_IntegrationConfig.buildHttpRequest(
                configName, inputRecordId, correlationId, requestBody
            );
            System.debug(LoggingLevel.DEBUG, '### CompleteOrder REQUEST BODY ###\n' + JSON.serializePretty(requestDTO));

            HttpResponse res = new Http().send(req);

            Integer statusCode   = res.getStatusCode();
            String  responseBody = res.getBody();
            String  endpoint     = SIAE_UTIL_IntegrationConfig.getCalloutEndpoint(configName);

            industriesintegrationfwk.IntegrationCalloutResponse calloutResponse;
            // 202 Accepted: lo step DRO resta Running in attesa della callback.
            if (statusCode == HTTP_ACCEPTED || statusCode == 200) {
                persistReceiptPackageId(orderId, responseBody);
                calloutResponse = SIAE_UTIL_IntegrationConfig.buildCalloutResponse(true, 200, null);
            } else {
                calloutResponse = SIAE_UTIL_IntegrationConfig.buildCalloutResponse(
                    false, statusCode, SIAE_UTIL_IntegrationConfig.parseErrorMessage(statusCode, responseBody)
                );
            }
            SIAE_UTIL_Log.logRequestResponse(correlationId, endpoint, 'POST', orderId, requestBody, responseBody, statusCode, 'SIAE_REST_CompleteOrder');
            return calloutResponse;

        } catch (Exception ex) {
            SIAE_UTIL_Log.logException(ex, correlationId, String.valueOf(orderId), 'SIAE_REST_CompleteOrder');
            return SIAE_UTIL_IntegrationConfig.buildCalloutResponse(false, 500, ex.getMessage());
        }
    }

    public static String buildRequestBody(Id orderId) {
        Order ord = loadOrder(orderId);
        return JSON.serializePretty(buildRequest(ord, null));
    }

    public static String extractStepId(String raw) {
        if (raw == null) { return null; }
        if (raw.startsWith('callout:') && raw.endsWith(':') && raw.length() > 9) {
            return raw.substring(8, raw.length() - 1);
        }
        return raw;
    }

    @TestVisible
    private static CompleteOrderRequestDTO buildRequest(Order ord, String requestGuid) {
        SalesforceCompleteOrderDTO sfDTO = new SalesforceCompleteOrderDTO();
        String actualStepId = extractStepId(requestGuid);
        String stepId = '';
        if(!String.isBlank(actualStepId)){
            List<FulfillmentStepDependency> listOfFulfillmentStepDep = new List<FulfillmentStepDependency>([SELECT Id, DependentStep.Name, DependentStepId FROM FulfillmentStepDependency WHERE DependsOnStepId =: actualStepId ]);
            stepId = !listOfFulfillmentStepDep.isEmpty() ? String.valueOf(listOfFulfillmentStepDep[0].DependentStepId) : '';
        }
        sfDTO.orderId            = ord.Id;
        sfDTO.stepId             = stepId;
        sfDTO.idSchede           = buildIdSchede(ord);
        sfDTO.idCrmOrganizzatore = resolveIdCrmOrganizzatore(ord);

        NotificaMovimentoAsyncDTO asyncDTO = new NotificaMovimentoAsyncDTO();
        asyncDTO.requestDTO = extractRequestDTO(ord);
        asyncDTO.salesforce = sfDTO;

        CompleteOrderRequestDTO requestDTO = new CompleteOrderRequestDTO();
        requestDTO.notificaMovimento_async = asyncDTO;
        return requestDTO;
    }

    @TestVisible
    private static List<Long> buildIdSchede(Order ord) {
        List<Long> idSchede = new List<Long>();
        if (ord.OrderItems == null) {
            return idSchede;
        }
        Boolean includeDc = ord.SIAE_IncludeDC__c == true;

        for (OrderItem oi : ord.OrderItems) {
            Long ddaId = SIAE_UTIL_IntegrationConfig.parseLongOrNull(oi.SIAE_DDACardId__c);
            if (ddaId != null) {
                idSchede.add(ddaId);
            }
            if (includeDc) {
                Long dcId = SIAE_UTIL_IntegrationConfig.parseLongOrNull(oi.SIAE_DCCardId__c);
                if (dcId != null) {
                    idSchede.add(dcId);
                }
            }
        }
        return idSchede;
    }

    @TestVisible
    private static Object extractRequestDTO(Order ord) {
        String raw = ord.SIAE_NotifyPaymentResp__c;
        if (String.isBlank(raw)) {
            throw new CompleteOrderException(
                'Order.SIAE_NotifyPaymentResp__c is blank — impossibile costruire requestDTO.'
            );
        }

        Object parsed;
        try {
            parsed = JSON.deserializeUntyped(raw);
        } catch (Exception ex) {
            throw new CompleteOrderException(
                'Order.SIAE_NotifyPaymentResp__c non è un JSON valido: ' + ex.getMessage()
            );
        }

        if (!(parsed instanceof Map<String, Object>)) {
            throw new CompleteOrderException(
                'Order.SIAE_NotifyPaymentResp__c: struttura JSON inattesa (atteso oggetto).'
            );
        }

        Map<String, Object> root  = (Map<String, Object>) parsed;
        Object asyncNode = root.get(NODE_ASYNC);
        if (!(asyncNode instanceof Map<String, Object>)) {
            throw new CompleteOrderException(
                'Order.SIAE_NotifyPaymentResp__c: nodo "' + NODE_ASYNC + '" mancante o non valido.'
            );
        }

        Object requestNode = ((Map<String, Object>) asyncNode).get(NODE_REQUEST);
        if (requestNode == null) {
            throw new CompleteOrderException(
                'Order.SIAE_NotifyPaymentResp__c: nodo "' + NODE_ASYNC + '.' + NODE_REQUEST + '" mancante.'
            );
        }
        return requestNode;
    }

    private static void persistReceiptPackageId(Id orderId, String responseBody) {
        if (String.isBlank(responseBody)) {
            return;
        }
        try {
            CompleteOrderResponseDTO responseDTO =
                (CompleteOrderResponseDTO) JSON.deserialize(responseBody, CompleteOrderResponseDTO.class);
            if (responseDTO != null && responseDTO.idPacchettoQuietanza != null) {
                update new Order(
                    Id                       = orderId,
                    SIAE_ReceiptPackageId__c = String.valueOf(responseDTO.idPacchettoQuietanza)
                );
            }
        } catch (Exception ex) {
            System.debug(LoggingLevel.WARN,
                '### CompleteOrder: idPacchettoQuietanza non persistito: ' + ex.getMessage());
        }
    }

    private static Long resolveIdCrmOrganizzatore(Order ord) {
        String idCrm = (ord.Account != null) ? ord.Account.SIAE_IDCRM__c : null;
        Long parsed = SIAE_UTIL_IntegrationConfig.parseLongOrNull(idCrm);
        if (parsed == null) {
            throw new CompleteOrderException(
                'idCrmOrganizzatore non risolto: Order.Account.SIAE_IDCRM__c mancante o non numerico.'
            );
        }
        return parsed;
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    private static Order loadOrder(Id orderId) {
        List<Order> orders = [
            SELECT Id,
                   Status,
                   SIAE_IncludeDC__c,
                   SIAE_NotifyPaymentResp__c,
                   Account.SIAE_IDCRM__c,
                   (SELECT Id, SIAE_DDACardId__c, SIAE_DCCardId__c
                    FROM OrderItems
                    ORDER BY CreatedDate ASC, Id ASC)
            FROM Order
            WHERE Id = :orderId
            LIMIT 1
        ];
        if (orders.isEmpty()) {
            throw new CompleteOrderException('Order non trovato per Id: ' + orderId);
        }
        return orders[0];
    }
}