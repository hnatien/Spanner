import Testing
@testable import SpannerCore

@Suite("DDC packets")
struct DDCPacketTests {
    @Test func setPacketMatchesTheMCCSLayout() {
        // 0x3F = 0x6E ^ 0x51; checksum covers header, opcode and payload.
        let packet = DDC.setPacket(.brightness, value: 0x0032)
        #expect(packet == [0x84, 0x03, 0x10, 0x00, 0x32, 0x3F ^ 0x84 ^ 0x03 ^ 0x10 ^ 0x00 ^ 0x32])
    }

    @Test func getPacketIsChecksummedFromTheDestinationOnly() {
        #expect(DDC.getPacket(.volume) == [0x82, 0x01, 0x62, 0x6E ^ 0x82 ^ 0x01 ^ 0x62])
    }

    func reply(feature: UInt8, max: UInt16, current: UInt16, result: UInt8 = 0) -> [UInt8] {
        var bytes: [UInt8] = [0x6E, 0x88, 0x02, result, feature, 0x00,
                              UInt8(max >> 8), UInt8(max & 0xFF), UInt8(current >> 8), UInt8(current & 0xFF)]
        bytes.append(bytes.reduce(0x50, ^))
        return bytes
    }

    @Test func parsesAValidReply() {
        let reading = DDC.parseReply(reply(feature: 0x10, max: 100, current: 70), for: .brightness)
        #expect(reading == DDC.Reading(current: 70, maximum: 100))
        #expect(reading?.fraction == 0.7)
    }

    @Test func rejectsCorruptOrMismatchedReplies() {
        var corrupt = reply(feature: 0x10, max: 100, current: 70)
        corrupt[9] ^= 0x01
        #expect(DDC.parseReply(corrupt, for: .brightness) == nil)
        #expect(DDC.parseReply(reply(feature: 0x62, max: 100, current: 70), for: .brightness) == nil)
        #expect(DDC.parseReply(reply(feature: 0x10, max: 100, current: 70, result: 1), for: .brightness) == nil)
        #expect(DDC.parseReply([UInt8](repeating: 0, count: 11), for: .brightness) == nil)
        #expect(DDC.parseReply([0x01], for: .brightness) == nil)
    }

    @Test func valuesScaleToTheMonitorsMaximum() {
        #expect(DDC.value(for: 0.5, maximum: 100) == 50)
        #expect(DDC.value(for: 2, maximum: 80) == 80)
        #expect(DDC.value(for: -1, maximum: 80) == 0)
        #expect(DDC.Reading(current: 5, maximum: 0).fraction == 0)
    }
}

@Suite("Display to DDC service matching")
struct DisplayMatcherTests {
    typealias Display = DisplayServiceMatcher.Display
    typealias Service = DisplayServiceMatcher.Service

    @Test func serialNumbersDecideBetweenIdenticalMonitors() {
        let displays = [Display(id: 1, vendor: 0x10AC, model: 1, serial: 111, name: "DELL U2723QE"),
                        Display(id: 2, vendor: 0x10AC, model: 1, serial: 222, name: "DELL U2723QE")]
        let services = [Service(index: 0, vendor: 0x10AC, serial: 222, name: "DELL U2723QE"),
                        Service(index: 1, vendor: 0x10AC, serial: 111, name: "DELL U2723QE")]
        #expect(DisplayServiceMatcher.match(displays: displays, services: services) == [1: 1, 2: 0])
    }

    @Test func differentVendorsNeverMatch() {
        let displays = [Display(id: 1, vendor: 0x10AC, model: 1, serial: 0, name: "Dell")]
        let services = [Service(index: 0, vendor: 0x4C2D, serial: nil, name: "Samsung")]
        #expect(DisplayServiceMatcher.match(displays: displays, services: services).isEmpty)
    }

    @Test func servicesWithoutAttributesPairInOrder() {
        let displays = [Display(id: 7, vendor: 1, model: 1, serial: 0, name: "A"),
                        Display(id: 9, vendor: 2, model: 1, serial: 0, name: "B")]
        let services = [Service(index: 0, vendor: nil, serial: nil, name: nil),
                        Service(index: 1, vendor: nil, serial: nil, name: nil)]
        #expect(DisplayServiceMatcher.match(displays: displays, services: services) == [7: 0, 9: 1])
    }

    @Test func eachServiceIsUsedOnce() {
        let displays = [Display(id: 1, vendor: 5, model: 1, serial: 0, name: "X"),
                        Display(id: 2, vendor: 5, model: 1, serial: 0, name: "X")]
        let services = [Service(index: 0, vendor: 5, serial: nil, name: "X")]
        let result = DisplayServiceMatcher.match(displays: displays, services: services)
        #expect(result.count == 1)
        #expect(result[1] == 0)
    }
}
