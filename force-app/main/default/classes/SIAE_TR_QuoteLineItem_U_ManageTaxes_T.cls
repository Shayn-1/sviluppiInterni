/**
 * @description Test class for SIAE_TR_QuoteLineItem_U_ManageTaxes.
 *              Logica: scatta su TotalTaxAmount change.
 *              Se QuoteItemTaxItem presente → persiste DA/DC/BolloDA/BolloDC/Bollo.
 *              Se assente → nessuna scrittura (no fallback).
 *              QuoteItemTaxItem non è inseribile via DML → inject via taxItemsByQliIdOverride.
 *              TotalTaxAmount è read-only su DML/put(); usare JSON.deserialize() per impostarlo in memoria.
 * @author      Gaetano Iuliano - gaetano.iuliano@nttdata.com
 * @group       NTT Data — SIAE
 */
@isTest
private class SIAE_TR_QuoteLineItem_U_ManageTaxes_T {

    private static final Integer BULK_COUNT = 251;

    @TestSetup
    static void setupTestData() {
        Account acc = SIAE_TestDataFactory.createAccount(true);
        Id standardPricebookId = Test.getStandardPricebookId();

        List<Opportunity> opps = SIAE_TestDataFactory.createOpportunities(new List<Account>{ acc }, 1, false);
        opps[0].Pricebook2Id = standardPricebookId;
        insert opps;

        Quote quote = SIAE_TestDataFactory.createQuote(opps[0], false);
        quote.Pricebook2Id = standardPricebookId;
        insert quote;

        Product2 prod = SIAE_TestDataFactory.createProduct(true);
        List<PricebookEntry> pbes = SIAE_TestDataFactory.createPricebookEntries(
            new List<Product2>{ prod }, standardPricebookId, true
        );

        SIAE_TestDataFactory.createQuoteLineItems(BULK_COUNT, quote, pbes[0], true);
    }

    // Helper: QLI in memoria con TotalTaxAmount impostato (campo read-only → JSON.deserialize)
    private static QuoteLineItem makeNewQli(QuoteLineItem source, Decimal totalTaxAmount) {
        Map<String, Object> data = new Map<String, Object>{
            'attributes'     => new Map<String, Object>{ 'type' => 'QuoteLineItem' },
            'Id'             => source.Id,
            'TotalTaxAmount' => totalTaxAmount
        };
        return (QuoteLineItem) JSON.deserialize(JSON.serialize(data), QuoteLineItem.class);
    }

    // Helper: inietta override QuoteItemTaxItem (non inseribile via DML in test)
    private static void injectTaxItems(List<QuoteLineItem> qlis, Decimal da, Decimal dc, Decimal bolloDA, Decimal bolloDC) {
        Map<Id, Map<String, Decimal>> injected = new Map<Id, Map<String, Decimal>>();
        for (QuoteLineItem qli : qlis) {
            injected.put(qli.Id, new Map<String, Decimal>{
                'DA'        => da,
                'DC'        => dc,
                'BOLLO_DDA' => bolloDA,
                'BOLLO_DC'  => bolloDC
            });
        }
        SIAE_TR_QuoteLineItem_U_ManageTaxes.taxItemsByQliIdOverride = injected;
    }

    // ─── QuoteItemTaxItem path ────────────────────────────────────────────

    @isTest
    static void shouldPersistAllSapFields_WhenQuoteItemTaxItemPresent_Bulk() {
        List<QuoteLineItem> dbQlis = [SELECT Id, TotalTaxAmount FROM QuoteLineItem];
        Assert.areEqual(BULK_COUNT, dbQlis.size(), 'Setup deve creare ' + BULK_COUNT + ' righe.');
        injectTaxItems(dbQlis, 106.96, 0.66, 2.00, 1.00);

        Map<Id, QuoteLineItem> oldMap = new Map<Id, QuoteLineItem>(dbQlis);
        List<QuoteLineItem> newQlis = new List<QuoteLineItem>();
        for (QuoteLineItem qli : dbQlis) {
            newQlis.add(makeNewQli(qli, 110.62));
        }

        Test.startTest();
        SIAE_TR_QuoteLineItem_U_ManageTaxes.updateTaxFields(newQlis, oldMap);
        Test.stopTest();

        SIAE_TR_QuoteLineItem_U_ManageTaxes.taxItemsByQliIdOverride = null;

        List<QuoteLineItem> updated = [
            SELECT SIAE_TotalTaxDA__c, SIAE_TotalTaxDC__c, SIAE_TotalTaxBolloDA__c, SIAE_TotalTaxBolloDC__c, SIAE_TotalTaxBollo__c
            FROM QuoteLineItem
        ];
        for (QuoteLineItem qli : updated) {
            Assert.areEqual(106.96, qli.SIAE_TotalTaxDA__c,      'DA da QuoteItemTaxItem SAP.');
            Assert.areEqual(0.66,   qli.SIAE_TotalTaxDC__c,      'DC da QuoteItemTaxItem SAP.');
            Assert.areEqual(2.00,   qli.SIAE_TotalTaxBolloDA__c, 'BolloDA da QuoteItemTaxItem SAP.');
            Assert.areEqual(1.00,   qli.SIAE_TotalTaxBolloDC__c, 'BolloDC da QuoteItemTaxItem SAP.');
            Assert.areEqual(3.00,   qli.SIAE_TotalTaxBollo__c,   'Bollo = BolloDA + BolloDC.');
        }
    }

    @isTest
    static void shouldNotUpdateFields_WhenNoQuoteItemTaxItem() {
        List<QuoteLineItem> dbQlis = [SELECT Id, TotalTaxAmount FROM QuoteLineItem LIMIT 1];
        SIAE_TR_QuoteLineItem_U_ManageTaxes.taxItemsByQliIdOverride = new Map<Id, Map<String, Decimal>>(); // nessun item

        Map<Id, QuoteLineItem> oldMap = new Map<Id, QuoteLineItem>(dbQlis);
        List<QuoteLineItem> newQlis = new List<QuoteLineItem>{ makeNewQli(dbQlis[0], 110.62) };

        Test.startTest();
        SIAE_TR_QuoteLineItem_U_ManageTaxes.updateTaxFields(newQlis, oldMap);
        Test.stopTest();

        SIAE_TR_QuoteLineItem_U_ManageTaxes.taxItemsByQliIdOverride = null;

        QuoteLineItem result = [SELECT SIAE_TotalTaxDA__c FROM QuoteLineItem WHERE Id = :dbQlis[0].Id];
        Assert.isNull(result.SIAE_TotalTaxDA__c, 'Nessun QuoteItemTaxItem → nessuna scrittura.');
    }

    // ─── No-op ───────────────────────────────────────────────────────────

    @isTest
    static void shouldNotUpdate_WhenTotalTaxAmountUnchanged() {
        List<QuoteLineItem> dbQlis = [SELECT Id, TotalTaxAmount FROM QuoteLineItem LIMIT 1];
        SIAE_TR_QuoteLineItem_U_ManageTaxes.taxItemsByQliIdOverride = null;
        Map<Id, QuoteLineItem> oldMap = new Map<Id, QuoteLineItem>(dbQlis);

        Test.startTest();
        SIAE_TR_QuoteLineItem_U_ManageTaxes.updateTaxFields(dbQlis, oldMap);
        Test.stopTest();

        QuoteLineItem result = [SELECT SIAE_TotalTaxDA__c FROM QuoteLineItem WHERE Id = :dbQlis[0].Id];
        Assert.isNull(result.SIAE_TotalTaxDA__c, 'TotalTaxAmount invariato → nessun aggiornamento.');
    }

    @isTest
    static void shouldHandleEmptyList() {
        Test.startTest();
        SIAE_TR_QuoteLineItem_U_ManageTaxes.updateTaxFields(
            new List<QuoteLineItem>(), new Map<Id, QuoteLineItem>()
        );
        Test.stopTest();
        Assert.isTrue(true, 'Lista vuota gestita senza eccezioni.');
    }

    // ─── Handler coverage ─────────────────────────────────────────────────

    @isTest
    static void shouldCoverQuoteLineItemHandlerUnusedMethodsAndFlags() {
        SIAE_TR_QuoteLineItem_Handler.triggerOff = false;
        SIAE_TR_QuoteLineItem_Handler handler = new SIAE_TR_QuoteLineItem_Handler();

        Assert.areEqual(false, handler.skipTrigger(),   'Default: trigger non skippato.');
        Assert.areEqual(false, handler.stopRecursion(), 'Default: no ricorsione bloccata.');

        SIAE_TR_QuoteLineItem_Handler.triggerOff = true;
        Assert.areEqual(true, handler.skipTrigger(), 'triggerOff=true → skip.');
        SIAE_TR_QuoteLineItem_Handler.triggerOff = false;

        handler.executedTrigger();
        handler.onBeforeInsert(new List<SObject>());
        handler.onBeforeUpdate(new Map<Id, SObject>(), new Map<Id, SObject>());
        handler.onBeforeDelete(new Map<Id, SObject>());
        handler.onAfterInsert(new Map<Id, SObject>());
        handler.onAfterDelete(new Map<Id, SObject>());
        handler.onAfterUndelete(new Map<Id, SObject>());
    }
}