import Combine
import SwiftUI
import Vision
import VisionKit

/**
 The `DocScanner` is a tool facilitating document scanning using the device's camera and handling the scanned document results.
 */
@MainActor
public struct DocScanner: UIViewControllerRepresentable {
    private let interpreter: ScanInterpreting?
    private let completionHandler: (Result<ScanResult?, Error>) -> Void
    private let resultStream: PassthroughSubject<ScanResult?, Error>?
    @Binding private var scanResult: ScanResult?
    @Binding private var shouldDismiss: Bool

    public typealias UIViewControllerType = VNDocumentCameraViewController
    
    public static var isSupported: Bool {
        VNDocumentCameraViewController.isSupported
    }
    
    /**
     Initializes a `DocScanner` view.
     
     - Parameters:
        - interpreter: An optional `ScanInterpreting` object for interpreting scan results.
        - scanResult: A binding to the scan result.
        - resultStream: An optional result stream for observing scan responses.
        - completion: A closure to handle the completion of scanning.
    */
    public init(with interpreter: ScanInterpreting? = nil,
                shouldDismiss: Binding<Bool> = Binding.constant(false),
                scanResult: Binding<ScanResult?> = Binding.constant(nil),
                resultStream: PassthroughSubject<ScanResult?, Error>? = nil,
                completion: @escaping (Result<ScanResult?, Error>) -> Void = { _ in }) {
        self.completionHandler = completion
        self._scanResult = scanResult
        self.resultStream = resultStream
        self.interpreter = interpreter
        self._shouldDismiss = shouldDismiss
    }
    
    public func makeUIViewController(context: UIViewControllerRepresentableContext<DocScanner>) -> VNDocumentCameraViewController {
        let viewController = VNDocumentCameraViewController()
        viewController.delegate = context.coordinator
        return viewController
    }
    
    public func updateUIViewController(_ uiViewController: VNDocumentCameraViewController,
                                       context: UIViewControllerRepresentableContext<DocScanner>) {
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(self, and: interpreter)
    }
  
    public final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate, @unchecked Sendable {
        private let docScanner: DocScanner
        private let interpreter: ScanInterpreting?
        
        init(_ docScanner: DocScanner, and interpreter: ScanInterpreting? = nil) {
            self.docScanner = docScanner
            self.interpreter = interpreter
        }
        
        /**
         Handles the completion of scanning with scanned document pages.
         
         - Parameters:
            - controller: The `VNDocumentCameraViewController` instance.
            - scan: The `VNDocumentCameraScan` containing scanned document pages.
         */
        public func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                                 didFinishWith scan: VNDocumentCameraScan) {
            guard let interpreter else {
                respond(with: scan, controller: controller)
                return
            }
            Task { @MainActor [weak self] in
                let response = await interpreter.parseAndInterpret(scans: scan)
                self?.respond(with: response, controller: controller)
            }
        }
        
        /**
         Handles the cancellation of scanning.
         
         - Parameter controller: The `VNDocumentCameraViewController` instance.
         */
        public func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            Task { @MainActor [weak self] in
                self?.respond(with: nil, controller: controller)
            }
        }
        
        /**
         Handles errors that might occur during scanning.
         
         - Parameters:
            - controller: The `VNDocumentCameraViewController` instance.
            - error: The error that occurred during scanning.
         */
        public func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                                 didFailWithError error: Error) {
            Task { @MainActor [weak self] in
                self?.docScanner.completionHandler(.failure(error))
                self?.docScanner.scanResult = nil
                self?.docScanner.resultStream?.send(completion: .failure(error))
                self?.docScanner.shouldDismiss.toggle()
                controller.dismiss(animated: true)
            }
        }
        
        /**
            Sends the interpreted scan response to the provided result stream and completion handler.
            
            - Parameter result: The interpreted scan response.
        */
        private func respond(with result: ScanResult?, controller: VNDocumentCameraViewController) {
            Task { @MainActor [weak self] in
                self?.docScanner.completionHandler(.success(result))
                self?.docScanner.scanResult = result
                self?.docScanner.resultStream?.send(result)
                self?.docScanner.shouldDismiss.toggle()
                controller.dismiss(animated: true)
            }
        }
    }
}
