public class PricingPaymentItem {
    public String itemCode;
    // Object preserves the native representation required by each catalog:
    // TTPP serializes Decimal amounts, while MdA currently serializes formatted Strings.
    public Object amount;
    public String type;
    public String eventGenre;
    public Decimal incidencePercentage;
    public String materialTaxClassification;
    public String revenueItemType;
    public String instrumentId;
    public String attributeCode;

    public class Wrapper {
        public List<PricingPaymentItem> paymentItems = new List<PricingPaymentItem>();
    }
}