import PhotosUI
import SwiftUI

struct ScanView: View {
    var goToLoad: () -> Void
    @State private var model = ScanModel()
    @State private var showSmartCamera = false
    @State private var showPhotoCamera = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var typedCode = ""
    @FocusState private var typing: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    scanBox
                    manualEntry
                    if model.isBusy {
                        Button("Stop", role: .cancel) { model.stop() }.buttonStyle(.bordered)
                    }
                    if let s = model.status {
                        HStack(alignment: .top, spacing: 10) {
                            if model.isBusy { ProgressView() }
                            Text(s).font(.subheadline)
                        }
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(alignment: .leading) { Rectangle().fill(model.statusIsError ? Theme.stop : Theme.tub).frame(width: 4) }
                        .accessibilityElement(children: .combine)
                    }
                    if let rec = model.current {
                        RecordView(record: rec, onLoad: goToLoad)
                            .id(rec.id + String(rec.product != nil))
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.bg)
            .navigationTitle("Washtag")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { typing = false }
                }
            }
            .fullScreenCover(isPresented: $showSmartCamera) {
                SmartCameraView { result in model.handle(result) }
            }
            .sheet(isPresented: $showPhotoCamera) {
                CameraPicker { model.analyze($0) }.ignoresSafeArea()
            }
            .onChange(of: pickerItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                        model.analyze(img)
                    }
                    pickerItem = nil
                }
            }
        }
    }

    private var scanBox: some View {
        VStack(spacing: 12) {
            if let img = model.image {
                Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: 260).clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Image(systemName: "camera.viewfinder").font(.system(size: 44)).foregroundStyle(Theme.tub)
                Text("Scan anything laundry").font(.headline)
                Text("Point the camera at a care label, a barcode, or a product like a detergent bottle. Washtag works out which it is.")
                    .font(.footnote).foregroundStyle(Theme.ink2).multilineTextAlignment(.center)
            }
            Button {
                typing = false
                if SmartCameraView.isAvailable { showSmartCamera = true } else { showPhotoCamera = true }
            } label: {
                Label("Scan", systemImage: "camera.viewfinder").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(model.isBusy)
            HStack {
                PhotosPicker(selection: $pickerItem, matching: .images) { Label("Choose photo", systemImage: "photo") }
                    .buttonStyle(.bordered)
                if model.image != nil && !model.isBusy {
                    Button { model.retry() } label: { Label("Read again", systemImage: "arrow.clockwise") }
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(18).frame(maxWidth: .infinity)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.stitch, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
    }

    private var manualEntry: some View {
        Panel(title: "Or type a barcode or item number") {
            HStack {
                TextField("e.g. 012345678905", text: $typedCode)
                    .keyboardType(.numbersAndPunctuation).textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled().textInputAutocapitalization(.characters)
                    .focused($typing).submitLabel(.search)
                    .onSubmit { lookUpTyped() }
                Button("Look up") { lookUpTyped() }.buttonStyle(.bordered).disabled(model.isBusy)
            }
            let v = typedCode.trimmingCharacters(in: .whitespaces)
            if !v.isEmpty {
                Text(typedHint(v)).font(.caption).foregroundStyle(GTIN.isValid(v) == false ? Theme.stop : Theme.ink2)
            }
        }
    }

    private func lookUpTyped() {
        typing = false
        model.lookUp(code: typedCode, via: .typed, thumbnail: nil)
    }

    private func typedHint(_ v: String) -> String {
        guard v.allSatisfy(\.isNumber) else { return "Not a barcode number — Washtag will search the web for it." }
        switch GTIN.isValid(v) {
        case true?: return "✓ Valid \(GTIN.type(v)) check digit"
        case false?: return "✕ Check digit doesn’t match — recheck the numbers, or Washtag will search the web for it as typed"
        case nil: return "\(v.count) digits — not a UPC/EAN length (12, 13 or 8), so Washtag will search the web for it"
        }
    }
}
