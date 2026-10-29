/**
 * @description       Test class for SIAE_REST_InboundPending
 * @author            Domenico Del Prete - domenico.delprete@nttdata.com
 * @group             NTT Data — SIAE
 * @createdDate       2026-06-30
 * @lastModifiedDate  2026-06-30
 * @lastModifiedBy    Domenico Del Prete
 */
@isTest
private class SIAE_REST_InboundPending_T {

    // ── getProviderAttributes ────────────────────────────────────────────────

    @isTest
    static void testGetProviderAttributes() {
        Test.startTest();
        List<industriesintegrationfwk.ApexProviderAttr> attrs =
            SIAE_REST_InboundPending.getProviderAttributes();
        Test.stopTest();

        System.assertNotEquals(null, attrs, 'Provider attributes must not be null');
        System.assertEquals(1, attrs.size(), 'Expected exactly 1 attribute');
    }

    // ── executeCallout — 202 Accepted (waiting for inbound callback) ─────────

    @isTest
    static void testExecuteCallout_Accepted202() {
        Test.startTest();
        industriesintegrationfwk.IntegrationCalloutResponse res =
            SIAE_REST_InboundPending.executeCallout('guid', 'recordId', 'payload', null, null);
        Test.stopTest();

        System.assertEquals(true, res.isSuccess(), 'Inbound pending must be treated as success');
        System.assertEquals(202, res.getResponseCode(), 'Status code must be 202 Accepted');
    }

    @isTest
    static void testExecuteCallout_NullArguments() {
        Map<String, Object> attrs = new Map<String, Object>{ 'integrationConfigName' => 'InboundApi' };

        Test.startTest();
        industriesintegrationfwk.IntegrationCalloutResponse res =
            SIAE_REST_InboundPending.executeCallout(null, null, null, attrs, null);
        Test.stopTest();

        System.assertEquals(true, res.isSuccess(), 'Must succeed even with null arguments');
        System.assertEquals(202, res.getResponseCode(), 'Status code must be 202 Accepted');
    }

    // ── executeCallout — error path (catch) ──────────────────────────────────

    @isTest
    static void testExecuteCallout_Exception() {
        SIAE_REST_InboundPending.throwForTest = true;

        Test.startTest();
        industriesintegrationfwk.IntegrationCalloutResponse res =
            SIAE_REST_InboundPending.executeCallout('guid', 'recordId', 'payload', null, null);
        Test.stopTest();

        System.assertEquals(false, res.isSuccess(), 'Exception path must not be a success');
        System.assertEquals(500, res.getResponseCode(), 'Status code must be 500 on exception');
        System.assertNotEquals(null, res.getErrorMessage(), 'Error message must be populated');
    }
}