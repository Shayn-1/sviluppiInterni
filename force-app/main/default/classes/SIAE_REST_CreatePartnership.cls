/**
 * @description       : 
 * @author            : Domenico Del Prete - domenico.delprete@nttdata.com
 * @group             : NTT Data
 * @last modified on  : 06-30-2026
 * @last modified by  : Domenico Del Prete - domenico.delprete@nttdata.com
**/
global with sharing class SIAE_REST_CreatePartnership
        implements industriesintegrationfwk.ProcessIntegrationProviderAdvanced {

    private static final String CONFIG_NAME         = 'CreatePartnership';
    private static final String RESULT_CODE_SUCCESS = '00';
    private static final String STATUS_INSERTED     = 'I';

    public class RequestDTO {
        public Long   ownerId;
        public String partnershipCode;
    }

    public class ResponseDTO {
        public Long           associationId;
        public Long           ownerId;
        public PartnershipDTO partnership;
        public String         status;
        public ResultDTO      result;
    }

    public class PartnershipDTO {
        public String partnershipId;
        public String partnershipCode;
    }

    public class ResultDTO {
        public String code;
        public String description;
    }

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
        Id lineItemId;
        String correlationId;
        try {
            // 1. Validate input
            if (String.isBlank(inputRecordId)) {
                throw new IllegalArgumentException('inputRecordId is required.');
            }
            lineItemId = (Id) inputRecordId;
            if (lineItemId.getSObjectType() != OrderItem.SObjectType) {
                throw new IllegalArgumentException('inputRecordId must be an OrderItem ID.');
            }

            // 2. Read Salesforce data
            OrderItem lineItem = [
                SELECT Id, SIAE_CommercialAgreementCode__c, Order.Account.SIAE_IDCRM__c
                FROM OrderItem
                WHERE Id = :lineItemId
                LIMIT 1
            ];

            String partnershipCode = lineItem.SIAE_CommercialAgreementCode__c;
            String idCrm           = lineItem.Order.Account.SIAE_IDCRM__c;

            // SIAE_CommercialAgreementCode__c vuoto: salta la logica e completa lo step
            if (String.isBlank(partnershipCode)) {
                return SIAE_UTIL_IntegrationConfig.buildCalloutResponse(true, 200, null);
            }
            if (partnershipCode.length() > 6) {
                throw new IllegalArgumentException('SIAE_CommercialAgreementCode__c exceeds max length of 6.');
            }
            if (String.isBlank(idCrm)) {
                throw new IllegalArgumentException('Account.SIAE_IDCRM__c is required on the Order Account.');
            }

            // 3. Get config
            String configName = SIAE_UTIL_IntegrationConfig.resolveConfigName(attributes, CONFIG_NAME);

            // 4. Build HttpRequest
            RequestDTO reqBody = new RequestDTO();
            reqBody.ownerId         = Long.valueOf(idCrm.trim());
            reqBody.partnershipCode = partnershipCode;
            String requestBody = JSON.serialize(reqBody);

            correlationId = UUID.randomUUID().toString();
            HttpRequest req = SIAE_UTIL_IntegrationConfig.buildHttpRequest(
                configName, inputRecordId, correlationId, requestBody
            );

            // 5. Execute callout
            HttpResponse res = new Http().send(req);

            Integer statusCode   = res.getStatusCode();
            String  responseBody = res.getBody();
            String  endpoint     = SIAE_UTIL_IntegrationConfig.getCalloutEndpoint(configName);

            // 6. Parse response and 7. Update OrderItem
            industriesintegrationfwk.IntegrationCalloutResponse calloutResponse;
            if (statusCode == 200) {
                ResponseDTO responseDTO =
                    (ResponseDTO) JSON.deserialize(responseBody, ResponseDTO.class);
                String  resultCode        = (responseDTO.result != null) ? responseDTO.result.code : null;
                Boolean isBusinessSuccess = responseDTO.result == null
                    || RESULT_CODE_SUCCESS == resultCode
                    || STATUS_INSERTED == responseDTO.status;

                OrderItem toUpdate = new OrderItem(Id = lineItemId);
                if (responseDTO.associationId != null) {
                    toUpdate.SIAE_AssociationId__c = String.valueOf(responseDTO.associationId);
                }
                if (responseDTO.partnership != null) {
                    toUpdate.SIAE_PartnershipId__c = responseDTO.partnership.partnershipId;
                }
                update toUpdate;

                String businessErrorMsg;
                if (!isBusinessSuccess) {
                    businessErrorMsg = resultCode + ': ' +
                        (responseDTO.result != null ? responseDTO.result.description : '');
                }

                calloutResponse = SIAE_UTIL_IntegrationConfig.buildCalloutResponse(
                    isBusinessSuccess, statusCode, businessErrorMsg
                );
            } else {
                calloutResponse = SIAE_UTIL_IntegrationConfig.buildCalloutResponse(
                    false, statusCode, SIAE_UTIL_IntegrationConfig.parseErrorMessage(statusCode, responseBody)
                );
            }
            // 8. Log request + response
            SIAE_UTIL_Log.logRequestResponse(correlationId, endpoint, 'POST', lineItemId, requestBody, responseBody, statusCode, 'SIAE_REST_CreatePartnership');
            return calloutResponse;

        } catch (Exception ex) {
            // 9. Handle unexpected exceptions (callout, DML, parse failures)
            SIAE_UTIL_Log.logException(ex, correlationId, String.valueOf(lineItemId), 'SIAE_REST_CreatePartnership');
            return SIAE_UTIL_IntegrationConfig.buildCalloutResponse(false, 500, ex.getMessage());
        }
    }

}