public with sharing class SIAE_UTIL_IntegrationConfig {

    public class ConfigNotFoundException extends Exception {}

    private static final Map<String, SIAE_IntegrationConfig__mdt> cache =
        new Map<String, SIAE_IntegrationConfig__mdt>();

    public static SIAE_IntegrationConfig__mdt getConfig(String configDeveloperName) {
        if (cache.containsKey(configDeveloperName)) {
            return cache.get(configDeveloperName);
        }
        List<SIAE_IntegrationConfig__mdt> configs = [
            SELECT DeveloperName, SIAE_NamedCredential__c, SIAE_EndpointPath__c,
                   SIAE_HttpMethod__c, SIAE_TimeoutMs__c, SIAE_SystemId__c, SIAE_IsActive__c
            FROM SIAE_IntegrationConfig__mdt
            WHERE DeveloperName = :configDeveloperName
            LIMIT 1
        ];
        if (configs.isEmpty() || !configs[0].SIAE_IsActive__c) {
            throw new ConfigNotFoundException(
                'Integration config not found or inactive: ' + configDeveloperName
            );
        }
        cache.put(configDeveloperName, configs[0]);
        return configs[0];
    }

    public static String getCalloutEndpoint(String configDeveloperName) {
        SIAE_IntegrationConfig__mdt cfg = getConfig(configDeveloperName);
        return 'callout:' + cfg.SIAE_NamedCredential__c + cfg.SIAE_EndpointPath__c;
    }

    public static String getNamedCredentialName(String configDeveloperName) {
        return getConfig(configDeveloperName).SIAE_NamedCredential__c;
    }

    public static String getEndpointPath(String configDeveloperName) {
        return getConfig(configDeveloperName).SIAE_EndpointPath__c;
    }

    public static String getHttpMethod(String configDeveloperName) {
        return getConfig(configDeveloperName).SIAE_HttpMethod__c;
    }

    public static Integer getTimeoutMs(String configDeveloperName) {
        return (Integer) getConfig(configDeveloperName).SIAE_TimeoutMs__c;
    }

    public static String getSystemId(String configDeveloperName) {
        return getConfig(configDeveloperName).SIAE_SystemId__c;
    }


    private static final String ATTR_INTEGRATION_CONFIG_NAME = 'integrationConfigName';

    /** DTO errore standard restituito dalle API Mulesoft non-2xx. */
    public class ErrorResponseDTO {
        public String code;
        public String message;
    }

    public static List<industriesintegrationfwk.ApexProviderAttr> buildProviderAttributes(String defaultConfigName) {
        return new List<industriesintegrationfwk.ApexProviderAttr>{
            new industriesintegrationfwk.ApexProviderAttr(
                'Integration Config Name', ATTR_INTEGRATION_CONFIG_NAME, defaultConfigName, true, 'String'
            )
        };
    }

    public static String resolveConfigName(Map<String, Object> attributes, String defaultConfigName) {
        if (attributes != null && attributes.containsKey(ATTR_INTEGRATION_CONFIG_NAME)) {
            Object value = attributes.get(ATTR_INTEGRATION_CONFIG_NAME);
            if (value != null && String.isNotBlank(String.valueOf(value))) {
                return String.valueOf(value);
            }
        }
        return defaultConfigName;
    }

    /**
     * Costruisce una HttpRequest POST verso l'endpoint del config indicato, con
     * gli header standard delle integrazioni SIAE Digital
     * (Content-Type, X-Correlation-ID, X-Transaction-ID, X-System-ID) e timeout.
     *
     * @param correlationId se blank ne viene generato uno nuovo (UUID).
     * @param body          body già serializzato (può essere null).
     */
    public static HttpRequest buildHttpRequest(
        String configName,
        String transactionId,
        String correlationId,
        String body
    ) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(getCalloutEndpoint(configName));
        req.setMethod(getHttpMethod(configName));
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('X-Correlation-ID', String.isBlank(correlationId) ? UUID.randomUUID().toString() : correlationId);
        req.setHeader('X-Transaction-ID', transactionId);
        req.setHeader('X-System-ID', getSystemId(configName));
        req.setTimeout(getTimeoutMs(configName));
        if (body != null) {
            req.setBody(body);
        }
        return req;
    }

    public static industriesintegrationfwk.IntegrationCalloutResponse buildCalloutResponse(
        Boolean success,
        Integer statusCode,
        String errorMessage
    ) {
        industriesintegrationfwk.IntegrationCalloutResponse response =
            new industriesintegrationfwk.IntegrationCalloutResponse(success);
        response.setResponseCode(statusCode);
        if (String.isNotBlank(errorMessage)) {
            response.setErrorMessage(errorMessage);
        }
        return response;
    }

    public static String parseErrorMessage(Integer statusCode, String responseBody) {
        try {
            ErrorResponseDTO err = (ErrorResponseDTO) JSON.deserialize(responseBody, ErrorResponseDTO.class);
            if (err != null && (String.isNotBlank(err.code) || String.isNotBlank(err.message))) {
                return (String.isNotBlank(err.code) ? err.code + ': ' : '') + err.message;
            }
        } catch (Exception parseEx) {
            // fallback sotto
        }
        return 'HTTP ' + statusCode + ': ' + responseBody;
    }

    public static Long parseLongOrNull(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            return Long.valueOf(value.trim());
        } catch (Exception ex) {
            return null;
        }
    }

    public static Decimal parseDecimalOrNull(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            return Decimal.valueOf(value.trim());
        } catch (Exception ex) {
            return null;
        }
    }
}