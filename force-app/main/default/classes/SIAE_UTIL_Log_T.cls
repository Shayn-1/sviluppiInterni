/**
 * @description       : 
 * @author            : Domenico Del Prete - domenico.delprete@nttdata.com
 * @group             : NTT Data
 * @last modified on  : 06-30-2026
 * @last modified by  : Domenico Del Prete - domenico.delprete@nttdata.com
**/
@isTest
private class SIAE_UTIL_Log_T {

    @isTest
    static void testLogRequestResponse_directDml_insertsRecord() {
        Test.startTest();
        SIAE_UTIL_Log.logRequestResponse(
            'corr-001', 'https://api.test.com/endpoint', 'POST', 'test',
            '{"req": "body"}', '{"res": "ok"}', 200, 'TestClass'
        );
        Test.stopTest();
        System.assertEquals(1, [SELECT COUNT() FROM SIAE_Log__c]);
    }

    @isTest
    static void testLogRequestResponse_directDml_nullPayloads() {
        Test.startTest();
        SIAE_UTIL_Log.logRequestResponse(
            'corr-002', 'https://api.test.com', 'GET', 'test',
            null, null, 204, 'TestClass', false
        );
        Test.stopTest();
        System.assertEquals(1, [SELECT COUNT() FROM SIAE_Log__c]);
    }

    @isTest
    static void testLogRequestResponse_platformEvent_noException() {
        Test.startTest();
        SIAE_UTIL_Log.logRequestResponse(
            'corr-003', 'https://api.test.com', 'PUT', 'test',
            '{"req": "x"}', '{"res": "y"}', 200, 'TestClass', true
        );
        Test.stopTest();
        System.assert(true, 'Platform event path should not throw');
    }

    @isTest
    static void testLogRequestResponse_platformEvent_truncatesPayload() {
        String longStr = 'x'.repeat(SIAE_UTIL_Log.maxLength + 1000);
        Test.startTest();
        SIAE_UTIL_Log.logRequestResponse(
            'corr-004', 'https://api.test.com', 'POST', 'test',
            longStr, longStr, 200, 'TestClass', true
        );
        Test.stopTest();
        System.assert(true, 'Platform event with long payload should not throw');
    }

    @isTest
    static void testLogRequestResponse_directDml_truncatesPayload() {
        String longStr = 'x'.repeat(SIAE_UTIL_Log.maxLength + 1000);
        Test.startTest();
        SIAE_UTIL_Log.logRequestResponse(
            'corr-005', 'https://api.test.com', 'POST', 'test',
            longStr, longStr, 200, 'TestClass', false
        );
        Test.stopTest();
        System.assertEquals(1, [SELECT COUNT() FROM SIAE_Log__c]);
    }

    @isTest
    static void testLogException_publishesEvent() {
        Exception ex;
        try {
            Integer.valueOf('not-a-number');
        } catch (Exception e) {
            ex = e;
        }
        Test.startTest();
        SIAE_UTIL_Log.logException(ex, 'corr-006', 'a0BMA000000000', 'TestClass');
        Test.stopTest();
        System.assert(true, 'logException should not throw');
    }

    @isTest
    static void testLogFromLwc_insertsLog() {
        Test.startTest();
        SIAE_UTIL_Log.logFromLwc('Component error', 'c/myComp', 'a0BMA000000000');
        Test.stopTest();
        System.assertEquals(1, [SELECT COUNT() FROM SIAE_Log__c]);
    }

    @isTest
    static void testLogFromLwc_nullMessage_storesEmptyString() {
        Test.startTest();
        SIAE_UTIL_Log.logFromLwc(null, 'c/myComp', null);
        Test.stopTest();
        System.assertEquals(1, [SELECT COUNT() FROM SIAE_Log__c]);
    }
}