/**
 * @description      Apex class for set fulfillment step in pending and waiting for inbound api
 * @author           Domenico Del Prete - domenico.delprete@nttdata.com
 * @group            NTT Data — SIAE
 * @createdDate      2026-06-30
 * @lastModifiedDate 2026-06-30
 * @lastModifiedBy   Domenico Del Prete
 */
global with sharing class SIAE_REST_InboundPending implements industriesintegrationfwk.ProcessIntegrationProviderAdvanced {


    private static final String CONFIG_NAME = 'InboundApi';

    // Hook di test per forzare il percorso di errore (catch) — vedi SIAE_REST_InboundPending_T.
    @TestVisible
    private static Boolean throwForTest = false;

    // ── Provider attributes ─────────────────────────────────────────────────

    global static List<industriesintegrationfwk.ApexProviderAttr> getProviderAttributes() {
        return SIAE_UTIL_IntegrationConfig.buildProviderAttributes(CONFIG_NAME);
    }

    // ── Callout ─────────────────────────────────────────────────────────────

    global static industriesintegrationfwk.IntegrationCalloutResponse executeCallout(String requestGuid, String inputRecordId, String payload, Map<String, Object> attributes, industriesintegrationfwk.HttpBaseProvider httpProvider
    ) {
        String correlationId = 'Waiting Inbound Callback';
        try {

            if (throwForTest) {
                throw new CalloutException('Forced test exception');
            }
            industriesintegrationfwk.IntegrationCalloutResponse calloutResponse;
            calloutResponse = SIAE_UTIL_IntegrationConfig.buildCalloutResponse(true, 202, null);
            return calloutResponse;
        } catch (Exception ex) {
            SIAE_UTIL_Log.logException(ex, correlationId, String.valueOf(inputRecordId), 'SIAE_REST_CompleteOrder');
            return SIAE_UTIL_IntegrationConfig.buildCalloutResponse(false, 500, ex.getMessage());
        }
    }

   
}