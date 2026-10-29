/**
 * @description Aggiorna i campi custom di tassazione SIAE su QuoteLineItem.
 *              Quando RLM aggiorna TotalTaxAmount, legge QuoteItemTaxItem (stessa transazione)
 *              per ottenere il breakdown SAP: DA, DC, BOLLO_DDA, BOLLO_DC.
 *              Se QuoteItemTaxItem assente (SAP non ha risposto), i campi custom non vengono toccati.
 * @author      Gaetano Iuliano - gaetano.iuliano@nttdata.com
 * @group       NTT Data — SIAE
 */
public class SIAE_TR_QuoteLineItem_U_ManageTaxes {

    // Iniettabile nei test (QuoteItemTaxItem non è inseribile via DML).
    @TestVisible
    private static Map<Id, Map<String, Decimal>> taxItemsByQliIdOverride = null;

    public static void updateTaxFields(List<QuoteLineItem> newRecords, Map<Id, QuoteLineItem> oldMap) {
        List<QuoteLineItem> toUpdate = new List<QuoteLineItem>();

        Set<Id> changedIds = new Set<Id>();
        for (QuoteLineItem qli : newRecords) {
            if (qli.TotalTaxAmount != oldMap.get(qli.Id).TotalTaxAmount) {
                changedIds.add(qli.Id);
            }
        }
        if (changedIds.isEmpty()) return;

        Map<Id, Map<String, Decimal>> taxByQliId = queryTaxItems(changedIds);

        for (QuoteLineItem qli : newRecords) {
            Map<String, Decimal> taxMap = taxByQliId.get(qli.Id);
            if (taxMap == null || taxMap.isEmpty()) continue;

            Decimal da      = taxMap.containsKey('DA')        ? taxMap.get('DA')        : 0;
            Decimal dc      = taxMap.containsKey('DC')        ? taxMap.get('DC')        : 0;
            Decimal bolloDA = taxMap.containsKey('BOLLO_DDA') ? taxMap.get('BOLLO_DDA') : 0;
            Decimal bolloDC = taxMap.containsKey('BOLLO_DC')  ? taxMap.get('BOLLO_DC')  : 0;
            toUpdate.add(new QuoteLineItem(
                Id                      = qli.Id,
                SIAE_TotalTaxDA__c      = da,
                SIAE_TotalTaxDC__c      = dc,
                SIAE_TotalTaxBolloDA__c = bolloDA,
                SIAE_TotalTaxBolloDC__c = bolloDC,
                SIAE_TotalTaxBollo__c   = bolloDA + bolloDC
            ));
        }

        if (!toUpdate.isEmpty()) update toUpdate;
    }

    private static Map<Id, Map<String, Decimal>> queryTaxItems(Set<Id> qliIds) {
        if (taxItemsByQliIdOverride != null) {
            return taxItemsByQliIdOverride;
        }
        Map<Id, Map<String, Decimal>> result = new Map<Id, Map<String, Decimal>>();
        for (QuoteItemTaxItem item : [
            SELECT QuoteLineItemId, Name, Amount
            FROM QuoteItemTaxItem
            WHERE QuoteLineItemId IN :qliIds
        ]) {
            Id qliId = item.QuoteLineItemId;
            if (!result.containsKey(qliId)) result.put(qliId, new Map<String, Decimal>());
            result.get(qliId).put(item.Name, item.Amount);
        }
        return result;
    }
}