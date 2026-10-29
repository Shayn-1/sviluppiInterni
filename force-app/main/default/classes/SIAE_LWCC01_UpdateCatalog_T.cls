/**
 * @description       : Test class for LWC Apex Controller SIAE_LWCC01_UpdateCatalog
 * @author            : Domenico Del Prete - domenico.delprete@nttdata.com
 * @group             : NTT Data
 * @last modified on  : 02-18-2026
 * @last modified by  : Domenico Del Prete - domenico.delprete@nttdata.com
**/
@isTest
public class SIAE_LWCC01_UpdateCatalog_T {
    
    @TestSetup
    static void makeData(){
        ProductCatalog catalog = new ProductCatalog(
            Name = 'Test Catalog'
        );
        insert catalog;
    }

    @IsTest
    static void sendPlatformEvent(){
        List<ProductCatalog> catalogList = new List<ProductCatalog>([SELECT Id FROM ProductCatalog]);
        String catalogId = !catalogList.isEmpty() ? catalogList[0].Id : ''; 
        Test.startTest();
        SIAE_LWCC001_UpdateCatalog.PublishResult wr = SIAE_LWCC001_UpdateCatalog.publishEvent (catalogId);
        System.assertEquals(true, wr.success);
        Test.stopTest();
    }

    @IsTest
    static void sendPlatformEventWithoutCatalogId(){
        String catalogId = ''; 
        Test.startTest();
        SIAE_LWCC001_UpdateCatalog.PublishResult wr = SIAE_LWCC001_UpdateCatalog.publishEvent (catalogId);
        System.assertEquals(false, wr.success);
        Test.stopTest();
    }  
}