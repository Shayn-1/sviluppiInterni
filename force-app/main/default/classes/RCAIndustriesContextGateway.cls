public class RCAIndustriesContextGateway implements RCAContextGateway {
    private Context.IndustriesContext context;

    public RCAIndustriesContextGateway() {
        context = new Context.IndustriesContext();
    }

    public Map<String, Object> queryTags(Map<String, Object> input) {
        return context.queryTags(input);
    }

    public void updateContextAttributes(Map<String, Object> input) {
        context.updateContextAttributes(input);
    }
}