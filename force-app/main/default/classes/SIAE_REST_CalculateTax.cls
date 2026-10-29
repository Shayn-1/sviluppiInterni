/**
 * @description Client REST per il calcolo della tassazione dei preventivi verso SAP (servizio Fatt14),
 *              orchestrato da Mulesoft. Riceve i dati del carrello e delle righe di preventivo e
 *              restituisce, per ciascuna riga, imposte DDA, imposte DC e bollo DDA/DC.
 * @author      Gaetano Iuliano - gaetano.iuliano@nttdata.com
 * @group       NTT Data — SIAE
 */
public with sharing class SIAE_REST_CalculateTax {

    private static final String CONFIG_NAME = 'CalculateTax';
    private static final String CLASS_NAME  = 'SIAE_REST_CalculateTax';

    // ─── Request DTO — i nomi dei membri DEVONO combaciare con le chiavi swagger (case-sensitive) ───
    public class Request {
        public String idSap;
        public String seprag;
        public String idCarrello;
        public Boolean flagNoBollo = false;
        public Boolean flagExtraTerritorialita = false;
        public List<QuoteLineItemRequest> quoteLineItem = new List<QuoteLineItemRequest>();
    }

    public class QuoteLineItemRequest {
        public String id;
        public String totaleDda;
        public String totaleDc;
        public List<VoceCosto> vociCostoDda = new List<VoceCosto>();
        public List<VoceCosto> vociCostoDc = new List<VoceCosto>();
    }

    public class VoceCosto {
        public String voceIncasso;
        public String quantita;
        public String importo;
    }

    // ─── Response DTO ───
    public class Response {
        public String idCarrello;
        public List<QuoteLineItemWrapper> quoteLineItem;
    }

    public class QuoteLineItemWrapper {
        public QuoteLineItemResponse payload;
    }

    public class QuoteLineItemResponse {
        public String id;
        public String importoImposteDda;
        public String importoImposteDc;
        public String importoBolloDda;
        public String importoBolloDc;
    }

    // ─── Esito callout ───
    public class CalculateTaxResult {
        public Boolean success = false;
        public Integer statusCode;
        public String  errorMessage;
        // chiave = QuoteLineItem.Id normalizzato a 15 char
        public Map<String, QuoteLineItemResponse> taxByLineId = new Map<String, QuoteLineItemResponse>();
    }

    /**
     * Esegue il callout sincrono a SAP/Mulesoft e restituisce le imposte per riga.
     */
    public static CalculateTaxResult calculate(Request requestBody) {
        CalculateTaxResult result = new CalculateTaxResult();

        if (requestBody == null || requestBody.quoteLineItem == null || requestBody.quoteLineItem.isEmpty()) {
            result.success = true;
            result.statusCode = 200;
            return result;
        }

        String correlationId = UUID.randomUUID().toString();
        String requestJson   = JSON.serialize(requestBody);
        String endpoint;
        Integer statusCode;
        String  responseBody;
        String quoteId;
        try {
            HttpRequest req = SIAE_UTIL_IntegrationConfig.buildHttpRequest(
                CONFIG_NAME, requestBody.idCarrello, correlationId, requestJson
            );
            req.setHeader('Accept', 'application/json');
            endpoint = req.getEndpoint();

            HttpResponse res = new Http().send(req);
            statusCode   = res.getStatusCode();
            responseBody = res.getBody();
            result.statusCode = statusCode;

            if (statusCode >= 200 && statusCode < 300) {
                Response parsed = (Response) JSON.deserialize(responseBody, Response.class);
                if (parsed != null && parsed.quoteLineItem != null) {
                    quoteId = parsed.idCarrello;
                    for (QuoteLineItemWrapper wrapper : parsed.quoteLineItem) {
                        if (wrapper == null || wrapper.payload == null) continue;
                        QuoteLineItemResponse line = wrapper.payload;
                        if (String.isNotBlank(line.id)) {
                            result.taxByLineId.put(line.id.left(15), line);
                        }
                    }
                }
                result.success = true;
            } else {
                result.success = false;
                result.errorMessage = SIAE_UTIL_IntegrationConfig.parseErrorMessage(statusCode, responseBody);
            }
        } catch (Exception ex) {
            result.success = false;
            result.errorMessage = ex.getMessage();
            safeLogException(ex, correlationId, requestBody.idCarrello);
            return result;
        }

        safeLogRequestResponse(correlationId, endpoint, quoteId, requestJson, responseBody, statusCode);
        return result;
    }

    private static void safeLogRequestResponse(
        String correlationId, String endpoint, String recordId, String requestJson, String responseBody, Integer statusCode
    ) {
        try {
            // usePlatformEvent = true: nel contesto TaxAdapter RLM non è consentito DML diretto
            SIAE_UTIL_Log.logRequestResponse(
                correlationId, endpoint, 'POST', recordId, requestJson, responseBody, statusCode, CLASS_NAME, true
            );
        } catch (Exception logEx) {
            System.debug(LoggingLevel.WARN, CLASS_NAME + ': logRequestResponse failed — ' + logEx.getMessage());
        }
    }

    private static void safeLogException(Exception ex, String correlationId, String recordId) {
        try {
            SIAE_UTIL_Log.logException(ex, correlationId, recordId, CLASS_NAME);
        } catch (Exception logEx) {
            System.debug(LoggingLevel.WARN, CLASS_NAME + ': logException failed — ' + logEx.getMessage());
        }
    }
}