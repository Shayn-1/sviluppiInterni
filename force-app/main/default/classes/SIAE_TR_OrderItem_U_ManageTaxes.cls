/**
 * @description Aggiorna i campi custom di tassazione SIAE su OrderItem.
 *              Quando RLM aggiorna TotalTaxAmount, legge OrderItemTaxLineItem (stessa transazione)
 *              per ottenere il breakdown SAP: DA, DC, BOLLO_DDA, BOLLO_DC.
 *              Se OrderItemTaxLineItem assente (SAP non ha risposto), i campi custom non vengono toccati.
 * @author      Gaetano Iuliano - gaetano.iuliano@nttdata.com
 * @group       NTT Data — SIAE
 */
public class SIAE_TR_OrderItem_U_ManageTaxes {

    // Iniettabile nei test (OrderItemTaxLineItem non è inseribile via DML).
    @TestVisible
    private static Map<Id, Map<String, Decimal>> taxItemsByOiIdOverride = null;

    public static void updateTaxFields(List<OrderItem> newRecords, Map<Id, OrderItem> oldMap) {
        List<OrderItem> toUpdate = new List<OrderItem>();

        Set<Id> changedIds = new Set<Id>();
        for (OrderItem oi : newRecords) {
            if (oi.TotalTaxAmount != oldMap.get(oi.Id).TotalTaxAmount) {
                changedIds.add(oi.Id);
            }
        }
        if (changedIds.isEmpty()) return;

        Map<Id, Map<String, Decimal>> taxByOiId = queryTaxItems(changedIds);

        for (OrderItem oi : newRecords) {
            Map<String, Decimal> taxMap = taxByOiId.get(oi.Id);
            if (taxMap == null || taxMap.isEmpty()) continue;

            Decimal da      = taxMap.containsKey('DA')        ? taxMap.get('DA')        : 0;
            Decimal dc      = taxMap.containsKey('DC')        ? taxMap.get('DC')        : 0;
            Decimal bolloDA = taxMap.containsKey('BOLLO_DDA') ? taxMap.get('BOLLO_DDA') : 0;
            Decimal bolloDC = taxMap.containsKey('BOLLO_DC')  ? taxMap.get('BOLLO_DC')  : 0;
            toUpdate.add(new OrderItem(
                Id                      = oi.Id,
                SIAE_TotalTaxDA__c      = da,
                SIAE_TotalTaxDC__c      = dc,
                SIAE_TotalTaxBolloDA__c = bolloDA,
                SIAE_TotalTaxBolloDC__c = bolloDC,
                SIAE_TotalTaxBollo__c   = bolloDA + bolloDC
            ));
        }

        if (!toUpdate.isEmpty()) update toUpdate;
    }

    private static Map<Id, Map<String, Decimal>> queryTaxItems(Set<Id> oiIds) {
        if (taxItemsByOiIdOverride != null) {
            return taxItemsByOiIdOverride;
        }
        Map<Id, Map<String, Decimal>> result = new Map<Id, Map<String, Decimal>>();
        for (OrderItemTaxLineItem item : [
            SELECT OrderItemId, Name, Amount
            FROM OrderItemTaxLineItem
            WHERE OrderItemId IN :oiIds
        ]) {
            Id oiId = item.OrderItemId;
            if (!result.containsKey(oiId)) result.put(oiId, new Map<String, Decimal>());
            result.get(oiId).put(item.Name, item.Amount);
        }
        return result;
    }
}