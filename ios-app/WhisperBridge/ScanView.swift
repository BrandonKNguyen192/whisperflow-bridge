import AVFoundation
import SwiftUI
import WhisperBridgeCore

struct ScanView: UIViewControllerRepresentable {
    let onFound: (Pairing.Parsed) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        ScannerViewController(onFound: onFound)
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}
}

final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let onFound: (Pairing.Parsed) -> Void
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var fallbackLabel: UILabel?

    init(onFound: @escaping (Pairing.Parsed) -> Void) {
        self.onFound = onFound
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        addCloseButton()
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    granted ? self.startSession() : self.showFallback("Camera access denied")
                }
            }
        default:
            showFallback("Camera access denied")
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    private func startSession() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            showFallback("Camera unavailable — use Paste pairing link")
            return
        }
        let session = AVCaptureSession()
        session.sessionPreset = .high
        let output = AVCaptureMetadataOutput()
        guard session.canAddInput(input), session.canAddOutput(output) else {
            showFallback("Camera unavailable — use Paste pairing link")
            return
        }
        session.addInput(input)
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        previewLayer = layer
        captureSession = session
        session.startRunning()
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue,
              let parsed = Pairing.parse(value) else { return }
        captureSession?.stopRunning()
        captureSession = nil
        onFound(parsed)
    }

    private func addCloseButton() {
        let button: UIButton
        if #available(iOS 26.0, *) {
            var config = UIButton.Configuration.glass()
            config.image = UIImage(systemName: "xmark")
            button = UIButton(configuration: config)
        } else {
            button = UIButton(type: .system)
            button.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
            button.tintColor = .white
        }
        button.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(button)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            button.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            button.widthAnchor.constraint(equalToConstant: 44),
            button.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func showFallback(_ text: String) {
        captureSession?.stopRunning()
        captureSession = nil
        let label = UILabel()
        label.text = text
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32)
        ])
        fallbackLabel = label
    }

    @objc private func closeTapped() {
        captureSession?.stopRunning()
        captureSession = nil
        dismiss(animated: true)
    }
}
