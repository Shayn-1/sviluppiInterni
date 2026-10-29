public interface RCAContextGateway {
    Map<String, Object> queryTags(Map<String, Object> input);
    void updateContextAttributes(Map<String, Object> input);
}