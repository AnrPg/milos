import Capacitor
import CoreNFC
import Foundation

/// ADR-173: writes a location's NFC door tag (`MilosNfc`, the same interface
/// as on Android). `write` opens the system NFC sheet, waits for a tag and
/// writes one URL record (`/c/<location>/n/<code>`). Reading needs no code:
/// iPhones read NDEF URL tags in the background and open universal links in
/// the app.
@objc(MilosNfcPlugin)
public class MilosNfcPlugin: CAPPlugin, CAPBridgedPlugin, NFCNDEFReaderSessionDelegate {
    public let identifier = "MilosNfcPlugin"
    public let jsName = "MilosNfc"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "isAvailable", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "write", returnType: CAPPluginReturnPromise),
    ]

    private var session: NFCNDEFReaderSession?
    private var pending: CAPPluginCall?
    private var message: NFCNDEFMessage?

    @objc func isAvailable(_ call: CAPPluginCall) {
        let available = NFCNDEFReaderSession.readingAvailable
        call.resolve(["available": available, "enabled": available])
    }

    @objc func write(_ call: CAPPluginCall) {
        guard let link = call.getString("url"), link.hasPrefix("https://"), let url = URL(string: link),
              let payload = NFCNDEFPayload.wellKnownTypeURIPayload(url: url)
        else {
            call.reject("An https link is required")
            return
        }
        guard NFCNDEFReaderSession.readingAvailable else {
            call.reject("NFC is not available", "unavailable")
            return
        }
        DispatchQueue.main.async {
            self.pending?.reject("Writing was replaced", "cancelled")
            self.pending = call
            self.message = NFCNDEFMessage(records: [payload])
            self.session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: false)
            self.session?.alertMessage = "Milos"
            self.session?.begin()
        }
    }

    // MARK: NFCNDEFReaderSessionDelegate

    public func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {}

    public func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) {}

    public func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        // A successful write invalidates too; `finish` has resolved by then.
        finish(error: (error as? NFCReaderError)?.code == .readerSessionInvalidationErrorUserCanceled ? "cancelled" : error.localizedDescription)
    }

    public func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
        guard tags.count == 1, let tag = tags.first, let message = message else {
            session.restartPolling()
            return
        }
        session.connect(to: tag) { error in
            if let error = error {
                session.invalidate(errorMessage: error.localizedDescription)
                return
            }
            tag.queryNDEFStatus { status, capacity, error in
                guard error == nil, status == .readWrite else {
                    session.invalidate(errorMessage: status == .readOnly ? "Read-only tag" : "Unsupported tag")
                    return
                }
                guard capacity >= message.length else {
                    session.invalidate(errorMessage: "Tag too small")
                    return
                }
                tag.writeNDEF(message) { error in
                    if let error = error {
                        session.invalidate(errorMessage: error.localizedDescription)
                    } else {
                        self.finish(error: nil)
                        session.invalidate()
                    }
                }
            }
        }
    }

    private func finish(error: String?) {
        DispatchQueue.main.async {
            guard let call = self.pending else { return }
            self.pending = nil
            self.message = nil
            self.session = nil
            if let error = error { call.reject(error, error == "cancelled" ? "cancelled" : "write_failed") } else { call.resolve() }
        }
    }
}
