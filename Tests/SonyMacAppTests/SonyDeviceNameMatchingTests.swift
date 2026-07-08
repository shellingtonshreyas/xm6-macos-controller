import XCTest
@testable import SonyMacApp

final class SonyDeviceNameMatchingTests: XCTestCase {
    func testRecognizesStandardModels() {
        XCTAssertTrue(SonyRFCOMMTransport.isLikelySonyHeadphone(named: "WH-1000XM6"))
        XCTAssertTrue(SonyRFCOMMTransport.isLikelySonyHeadphone(named: "WF-1000XM5"))
        XCTAssertTrue(SonyRFCOMMTransport.isLikelySonyHeadphone(named: "LinkBuds S"))
        XCTAssertTrue(SonyRFCOMMTransport.isLikelySonyHeadphone(named: "ULT WEAR"))
    }

    func testRecognizesCollexionEdition() {
        XCTAssertTrue(SonyRFCOMMTransport.isLikelySonyHeadphone(named: "1000X THE COLLEXION"))
    }

    func testRejectsNonSonyAndLEDuplicates() {
        XCTAssertFalse(SonyRFCOMMTransport.isLikelySonyHeadphone(named: "LE_WH-1000XM6"))
        XCTAssertFalse(SonyRFCOMMTransport.isLikelySonyHeadphone(named: "AirPods Pro"))
        XCTAssertFalse(SonyRFCOMMTransport.isLikelySonyHeadphone(named: "JBL Flip 6"))
    }
}
