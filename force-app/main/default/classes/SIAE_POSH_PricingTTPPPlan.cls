/**
 * Revenue Cloud Advanced POSH entry point for TTPP pricing.
 * Orchestrates RCA context I/O and delegates all TTPP business logic to TTPPPricingProcessor.
 */
global class SIAE_POSH_PricingTTPPPlan implements RevSignaling.SignalingApexProcessor {

    global RevSignaling.TransactionResponse execute(RevSignaling.TransactionRequest request) {
        String contextId = request == null ? null : request.ctxInstanceId;
        ProcessResult result = executeInternal(contextId, new RCAIndustriesContextGateway());
        return resp(RevSignaling.TransactionStatus.SUCCESS, result.message);
    }

    @TestVisible
    private static ProcessResult executeWithContextId(String contextId) {
        return executeInternal(contextId, new RCAIndustriesContextGateway());
    }

    @TestVisible
    private static ProcessResult executeInternal(String contextId, RCAContextGateway ctx) {
        validateContextId(contextId);

        RCASalesTransaction salesTransaction = new RCAContextReader(ctx).read(contextId);
        TTPPPricingProcessor.process(salesTransaction);

        List<Map<String, Object>> updates = RCAContextWriter.buildUpdates(salesTransaction);

        for (RCASalesTransaction.ItemNode item : salesTransaction.items) {
            System.debug(
                LoggingLevel.ERROR,
                '=== TTPP ITEM ATTRIBUTES [' + item.lineItemId + '] === ' +
                JSON.serializePretty(item.attributeToUpdate)
            );
        }

        System.debug(
            LoggingLevel.ERROR,
            '=== TTPP FINAL UPDATE === ' + JSON.serializePretty(updates)
        );

        updateContext(contextId, updates, ctx);
        return buildProcessResult(updates);
    }

    private static void validateContextId(String contextId) {
        if (String.isBlank(contextId)) {
            throw new TtppPricingEntryPointException('Missing ctxInstanceId.');
        }
    }

    private static void updateContext(
        String contextId,
        List<Map<String, Object>> updates,
        RCAContextGateway ctx
    ) {
        if (updates == null || updates.isEmpty()) return;
        ctx.updateContextAttributes(new Map<String, Object>{
            'contextId' => contextId,
            'nodePathAndAttributes' => updates
        });
    }

    private static ProcessResult buildProcessResult(List<Map<String, Object>> updates) {
        Integer updateCount = updates == null ? 0 : updates.size();
        return new ProcessResult('TTPP pricing applied. Context nodes updated: ' + updateCount + '.');
    }

    private static RevSignaling.TransactionResponse resp(
        RevSignaling.TransactionStatus status,
        String message
    ) {
        RevSignaling.TransactionResponse response = new RevSignaling.TransactionResponse();
        response.status = status;
        response.message = message;
        return response;
    }

    @TestVisible
    private class ProcessResult {
        @TestVisible String message;
        private ProcessResult(String message) { this.message = message; }
    }

    public class TtppPricingEntryPointException extends Exception { }
}