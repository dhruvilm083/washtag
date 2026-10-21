import PhotosUI
import SwiftUI

struct ScanView: View {
    var goToLoad: () -> Void
    @State private var model = ScanModel()
    @State private var showCamera = false
    @State private var showLiveScanner = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var typedCode = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    modePicker
                    Text(model.mode == .label
                         ? "Photograph the care label flat and in focus. If the symbols sit next to a barcode, keep both in frame — Washtag reads both."
                         : "Point the camera at the barcode, photograph it straight on, or type the numbers.")
                        .font(.footnote).foregroundStyle(Theme.ink2)
                    photoBox
                    if model.mode == .upc { manualEntry }
                    actionRow
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
            .background(Theme.bg)
            .navigationTitle("Washtag")
            .sheet(isPresented: $showCamera) { CameraPicker { model.setImage($0) }.ignoresSafeArea() }
            .sheet(isPresented: $showLiveScanner) {
                LiveBarcodeScanner { code in
                    showLiveScanner = false
                    model.lookUp(code: code, via: "on-device decoder")
                }
                .ignoresSafeArea()
            }
            .onChange(of: pickerItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self), let img = UIImage(data: data) { model.setImage(img) }
                }
            }
        }
    }

    private var modePicker: some View {
        HStack(spacing: 0) {
            modeButton(.label, "Care symbols", "Photo of a wash label", "tag")
            modeButton(.upc, "UPC / barcode", "Look up the product", "barcode")
        }
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.ink, lineWidth: 2))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func modeButton(_ m: ScanMode, _ title: String, _ sub: String, _ icon: String) -> some View {
        let on = model.mode == m
        return Button { model.mode = m } label: {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.title2)
                Text(title).font(.subheadline.bold())
                Text(sub).font(.caption).opacity(0.8)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .foregroundStyle(on ? Theme.bg : Theme.ink)
            .background(on ? Theme.ink : Color.clear)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var photoBox: some View {
        VStack(spacing: 12) {
            if let img = model.image {
                Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: 320).clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Text(model.mode == .label ? "Add a photo of the label" : "Add a photo of the barcode").font(.headline)
            }
            HStack {
                Button { showCamera = true } label: { Label("Take photo", systemImage: "camera") }
                    .buttonStyle(.borderedProminent)
                PhotosPicker(selection: $pickerItem, matching: .images) { Label("Choose photo", systemImage: "photo") }
                    .buttonStyle(.bordered)
            }
            if model.mode == .upc && LiveBarcodeScanner.isAvailable {
                Button { showLiveScanner = true } label: { Label("Scan live with camera", systemImage: "barcode.viewfinder") }
                    .buttonStyle(.bordered)
            }
        }
        .padding(18).frame(maxWidth: .infinity)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.stitch, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
    }

    private var manualEntry: some View {
        Panel(title: "Or type the number under the barcode") {
            HStack {
                TextField("e.g. 012345678905", text: $typedCode).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                Button("Look up") { model.lookUp(code: typedCode, via: "typed by you") }.buttonStyle(.bordered)
            }
            let v = typedCode.filter(\.isNumber)
            if !v.isEmpty {
                let ok = GTIN.isValid(v)
                Text(ok == nil ? "\(v.count) digits — UPC is 12, EAN is 13 or 8" : ok! ? "✓ Valid \(GTIN.type(v)) check digit" : "✕ Check digit doesn’t match — recheck the numbers")
                    .font(.caption).foregroundStyle(ok == false ? Theme.stop : Theme.ink2)
            }
        }
    }

    private var actionRow: some View {
        HStack {
            Button(model.mode == .label ? "Read label" : "Read barcode") { model.scanPhoto() }
                .buttonStyle(.borderedProminent)
                .disabled(model.image == nil || model.isBusy)
            if model.isBusy { Button("Stop", role: .cancel) { model.stop() }.buttonStyle(.bordered) }
        }
    }
}
