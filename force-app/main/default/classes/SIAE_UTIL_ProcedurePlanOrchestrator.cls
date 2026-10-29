/**
 * @description       : 
 * @author            : Domenico Del Prete - domenico.delprete@nttdata.com
 * @group             : NTT Data
 * @last modified on  : 03-04-2026
 * @last modified by  : Domenico Del Prete - domenico.delprete@nttdata.com
**/
global class SIAE_UTIL_ProcedurePlanOrchestrator implements RevSignaling.SignalingApexProcessor {

    public virtual class BaseException extends Exception {}
    public class OtherException extends BaseException {}
    
    public RevSignaling.TransactionResponse execute(RevSignaling.TransactionRequest request) {
        System.debug('Executing POSTHOOK');
        
        String contextId = request.ctxInstanceId;
        Context.IndustriesContext industriesContext = new Context.IndustriesContext();
        
        String randomDescription = 'via Post Apex Pricing Hook';

        // STEP 2 - Query SalesTransactionItem nodes
        Map<String, Object> inputQueryItem = new Map<String, Object>{
            'contextId' => contextId,
            'tags' => new List<String>{ 'SalesTransactionItem' }
        };
        Map<String, Object> itemQueryOutput = industriesContext.queryTags(inputQueryItem);
        Map<String, Object> itemQueryResult = (Map<String, Object>) itemQueryOutput.get('queryResult');
        List<Object> itemData = (List<Object>) itemQueryResult.get('SalesTransactionItem');

        System.debug('QLI itemData=' + itemData);

        Map<String, Object> inputQueryItemDetails = new Map<String, Object>{
            'contextId' => contextId,
            'tags' => new List<String>{ 'SalesTransactionItemDetail' }
        };
        Map<String, Object> itemQueryOutputDetails = industriesContext.queryTags(inputQueryItem);
        Map<String, Object> itemQueryResultDetails = (Map<String, Object>) itemQueryOutput.get('queryResult');
        List<Object> itemDataDetails = (List<Object>) itemQueryResult.get('SalesTransactionItemDetail');

        System.debug('QLI itemDataDetails=' + JSON.serialize(itemQueryResultDetails));


        // STEP 3 - Build update list
        List<Map<String, Object>> itemNodeUpdates = new List<Map<String, Object>>();

        for (Object itemObj : itemData) {
            Map<String, Object> itemNode = (Map<String, Object>) itemObj;
            List<Object> dataPath = (List<Object>) itemNode.get('dataPath');
            System.debug('Full item dataPath: ' + JSON.serialize(dataPath));

            Boolean matched = false;
            dataPath.remove(0); // Remove contextId

            itemNodeUpdates.add(new Map<String, Object>{
                'nodePath' => new Map<String, Object>{ 'dataPath' => dataPath },
                'attributes' => new List<Object>{
                    new Map<String, Object>{
                        'attributeName' => 'SalesTrxnItemDescription',
                        'attributeValue' => randomDescription
                    }
                }
            });
            matched = true;
            System.debug('AFTER UPDATE Full item dataPath: ' + JSON.serialize(itemNodeUpdates));
            if (!matched) {
                String itemCtxId = dataPath.size() > 1 ? String.valueOf(dataPath[1]) : 'UNKNOWN';
                System.debug('No DisplaySize match found for item ' + itemCtxId);
            }
        }

        // STEP 4 - Submit context update
        if (!itemNodeUpdates.isEmpty()) {
            Map<String, Object> updateInput = new Map<String, Object>{
                'contextId' => contextId,
                'nodePathAndAttributes' => itemNodeUpdates
            };

            System.debug('--- PREHOOK: SUBMITTING CONTEXT UPDATE ---');
            System.debug(JSON.serializePretty(updateInput));
            industriesContext.updateContextAttributes(updateInput);
        }

        RevSignaling.TransactionResponse response = new RevSignaling.TransactionResponse();
        response.status = RevSignaling.TransactionStatus.SUCCESS;
        //response.status = RevSignaling.TransactionStatus.FAILED;
        //response.message = 'An error occurred during the processing...';
        return response;
    }
}