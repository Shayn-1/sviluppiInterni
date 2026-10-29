/**
 * MdA Revenue Cloud POSH entry point.
 * Orchestrates RCA context I/O and delegates all MdA business logic to MdAPricingProcessor.
 */
global class SIAE_POSH_PricingMdAPlan implements RevSignaling.SignalingApexProcessor {

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
        if (String.isBlank(contextId)) {
            return new ProcessResult('Missing ctxInstanceId.');
        }

        RCASalesTransaction salesTransaction = new RCAContextReader(ctx).read(contextId);
        if (salesTransaction.items.isEmpty()) {
            return new ProcessResult('No SalesTransactionItem found.');
        }

        MdAPricingProcessor.process(salesTransaction);

        List<Map<String, Object>> updates = RCAContextWriter.buildUpdates(salesTransaction);
        if (updates.isEmpty()) {
            return new ProcessResult('No pricing attributes updated.');
        }
        new RCAContextWriter(ctx).write(contextId, salesTransaction);
        return new ProcessResult('Updated pricing attributes on ' + updates.size() + ' node(s).');
    }

    private static RevSignaling.TransactionResponse resp(RevSignaling.TransactionStatus status, String msg) {
        RevSignaling.TransactionResponse r = new RevSignaling.TransactionResponse();
        r.status = status;
        r.message = msg;
        return r;
    }

    @TestVisible
    private class ProcessResult {
        @TestVisible String message;
        private ProcessResult(String message) { this.message = message; }
    }
}