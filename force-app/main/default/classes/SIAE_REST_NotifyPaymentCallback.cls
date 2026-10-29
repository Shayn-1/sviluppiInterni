/**
 * @description      REST resource richiamata da Sport in callback dopo la notifica
 *                   pagamento (a valle del 202 di completa-ordine).
 *                   Completa lo step Order Manager e transita lo stato dell'Order.
 * @author           Gaetano Iuliano - gaetano.iuliano@nttdata.com
 * @group            NTT Data — SIAE
 * @createdDate      2026-06-15
 * @lastModifiedDate 2026-06-15
 * @lastModifiedBy   Gaetano Iuliano
 */
@RestResource(urlMapping='/SIAE/billingNotify/*')
global with sharing class SIAE_REST_NotifyPaymentCallback {

    private static final String STEP_STATE_COMPLETED = 'Completed';
    private static final String ORDER_STATUS_FATTURATO     = 'Fatturato';
    private static final String ORDER_STATUS_FATTURATO_DDA = 'Fatturato_DDA';

    global class CallbackRequest {
        public String orderId;
        public String status;
        public String stepId;
    }

    global class CallbackResponse {
        public Boolean success;
        public String  errorMessage;

        public CallbackResponse(Boolean success, String errorMessage) {
            this.success      = success;
            this.errorMessage = errorMessage;
        }
    }

    @HttpPost
    global static void updateOrderStatus() {
        RestRequest  req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');
        String correlationId = UUID.randomUUID().toString();
        String requestPayload = (req != null && req.requestBody != null)
            ? req.requestBody.toString()
            : null;

        try {
            CallbackRequest body = parseBody(req);

            if (body == null
                || String.isBlank(body.orderId)
                || String.isBlank(body.stepId)) {
                writeResponse(res, 400, false,
                    'Campi obbligatori mancanti: orderId e stepId sono richiesti.');
                return;
            }

            Id orderId = (Id) body.orderId;

            List<Order> listOfOrder = new List<Order>([SELECT Id, SIAE_IncludeDC__c FROM Order WHERE Id = :orderId]);
            if(listOfOrder.isEmpty()){
                 writeResponse(res, 400, false,
                    'Order not found.');
                return;
            }
            Order ord = listOfOrder[0];
            String finalStatus = (ord.SIAE_IncludeDC__c == true)
                ? ORDER_STATUS_FATTURATO
                : ORDER_STATUS_FATTURATO_DDA;

            Savepoint sp = Database.setSavepoint();
            try {
                update new FulfillmentStep(Id = (Id) body.stepId, State = STEP_STATE_COMPLETED);
                update new Order(Id = orderId, Status = finalStatus);
            } catch (Exception dmlEx) {
                Database.rollback(sp);
                throw dmlEx;
            }

            writeResponse(res, 200, true, '');
            String responsePayload = res.responseBody != null ? res.responseBody.toString() : null;
            SIAE_UTIL_Log.logRequestResponse(correlationId, req.requestURI, 'POST', orderId, requestPayload, responsePayload, 200, 'SIAE_REST_NotifyPaymentCallback');

        } catch (System.JSONException jsonEx) {
            writeResponse(res, 400, false, 'Body non valido: ' + jsonEx.getMessage());
            SIAE_UTIL_Log.logException(jsonEx, correlationId, null, 'SIAE_REST_NotifyPaymentCallback');
        } catch (System.StringException strEx) {
            // Id non valido (orderId/stepId malformati)
            writeResponse(res, 400, false, 'Id non valido: ' + strEx.getMessage());
            SIAE_UTIL_Log.logException(strEx, correlationId, null, 'SIAE_REST_NotifyPaymentCallback');
        } catch (Exception ex) {
            writeResponse(res, 500, false, ex.getMessage());
            SIAE_UTIL_Log.logException(ex, correlationId, null, 'SIAE_REST_NotifyPaymentCallback');
        }
    }

    private static CallbackRequest parseBody(RestRequest req) {
        if (req == null || req.requestBody == null) {
            return null;
        }
        String raw = req.requestBody.toString();
        if (String.isBlank(raw)) {
            return null;
        }
        return (CallbackRequest) JSON.deserialize(raw, CallbackRequest.class);
    }

    private static void writeResponse(RestResponse res, Integer statusCode, Boolean success, String errorMessage) {
        res.statusCode  = statusCode;
        res.responseBody = Blob.valueOf(JSON.serialize(new CallbackResponse(success, errorMessage)));
    }
}