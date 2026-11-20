import PhotosUI
import ShreddishCore
import SwiftData
import SwiftUI

/// Suivi des progrès (spec 017, FR-1708) : bilan des 30 derniers jours, mensurations, photos privées.
struct BodyProgressView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(sort: \WeightEntry.dayKey) var weights: [WeightEntry]
    @Query(sort: \BodyMeasurement.dayKey, order: .reverse) var measurements: [BodyMeasurement]
    @Query(sort: \ProgressPhoto.dayKey) var photos: [ProgressPhoto]
    @Query var plans: [WeeklyPlan]
    @State private var addingMeasurement = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var sharing = false
    @State private var sharePhotos = false

    private var report: MonthlyReport {
        let today = model.clock.today
        let meals = plans.flatMap(\.days).filter { $0.day <= today }.flatMap { day in day.meals.map { (day: day.day, status: $0.status) } }
        return MonthlyReport.make(
            today: today, weights: weights.map(\.point),
            measurements: measurements.map { (day: $0.day, waist: $0.waistCm) }, meals: meals
        )
    }

    var body: some View {
        List {
            reportSection
            measurementsSection
            photosSection
        }
        .themedList()
        .navigationTitle("Mes progrès")
        .sheet(isPresented: $addingMeasurement) { MeasurementEditView() }
        .sheet(isPresented: $sharing) {
            ShareCardSheet(title: "Mes progrès", card: ProgressShareCard(
                report: report,
                before: sharePhotos ? photos.first?.imageData.flatMap(UIImage.init(data:)) : nil,
                after: sharePhotos && photos.count > 1 ? photos.last?.imageData.flatMap(UIImage.init(data:)) : nil
            ))
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Partager mes chiffres", systemImage: "square.and.arrow.up") {
                        sharePhotos = false
                        sharing = true
                    }
                    if photos.count > 1 {
                        Button("Partager avec mes photos", systemImage: "photo.on.rectangle") {
                            sharePhotos = true
                            sharing = true
                        }
                    }
                } label: {
                    Label("Partager", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("shareProgress")
            }
        }
        .onChange(of: pickedPhoto) { Task { await savePhoto() } }
    }

    private var reportSection: some View {
        let report = report
        return Section {
            if let change = report.weightChange {
                LabeledContent("Poids", value: "\(change > 0 ? "+" : "")\(Format.number(change)) kg")
            } else {
                LabeledContent("Poids", value: "\(report.weighIns) pesée\(report.weighIns > 1 ? "s" : "")")
            }
            if let waist = report.waistChange {
                LabeledContent("Tour de taille", value: "\(waist > 0 ? "+" : "")\(Format.number(waist)) cm")
            }
            if let adherence = report.adherence {
                LabeledContent("Repas suivis", value: "\(Int((adherence * 100).rounded())) % (\(report.mealsEaten)/\(report.mealsPlanned))")
                    .accessibilityIdentifier("adherence")
            }
        } header: {
            ListHeader {
                Text("30 derniers jours")
            }
        } footer: {
            ListFooter {
                Text("Repas suivis : cochés « mangé » parmi ceux prévus jusqu'à aujourd'hui.")
            }
        }
    }

    private var measurementsSection: some View {
        Section {
            ForEach(measurements) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(Format.day(entry.day, calendar: model.clock.calendar)).font(Theme.text(.subheadline, .semibold))
                    Text(Self.summary(entry)).font(Theme.text(.caption)).foregroundStyle(Theme.muted)
                }
            }
            .onDelete { offsets in
                for index in offsets { context.delete(measurements[index]) }
                try? context.save()
            }
            Button("Ajouter des mensurations", systemImage: "ruler") { addingMeasurement = true }
                .accessibilityIdentifier("addMeasurement")
        } header: {
            ListHeader {
                Text("Mensurations")
            }
        } footer: {
            ListFooter {
                Text("Le matin, au même endroit, ruban à plat. Une fois par semaine suffit.")
            }
        }
    }

    private var photosSection: some View {
        Section {
            if let first = photos.first, let last = photos.last, first.id != last.id {
                HStack(spacing: 8) {
                    photoTile(first, label: "Avant")
                    photoTile(last, label: "Maintenant")
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            } else if let only = photos.first {
                photoTile(only, label: Format.day(only.day, calendar: model.clock.calendar))
            }
            PhotosPicker(selection: $pickedPhoto, matching: .images) {
                Label("Ajouter une photo", systemImage: "camera")
            }
            .accessibilityIdentifier("addProgressPhoto")
        } header: {
            ListHeader {
                Text("Photos")
            }
        } footer: {
            ListFooter {
                Text("Privées : gardées sur ton iPhone, jamais envoyées à l'IA. Même lumière et même pose à chaque fois.")
            }
        }
    }

    private func photoTile(_ photo: ProgressPhoto, label: String) -> some View {
        VStack(spacing: 4) {
            if let data = photo.imageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, minHeight: 200, maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityLabel("Photo du \(Format.day(photo.day, calendar: model.clock.calendar))")
            }
            Text(label).font(Theme.text(.caption, .semibold)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .contextMenu {
            Button("Supprimer la photo", systemImage: "trash", role: .destructive) {
                context.delete(photo)
                try? context.save()
            }
        }
    }

    private func savePhoto() async {
        guard let item = pickedPhoto, let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        // Réduite à 1600 px : assez pour comparer, légère pour iCloud.
        let jpeg = image.scaled(maxSide: 1600).jpegData(compressionQuality: 0.8) ?? data
        context.insert(ProgressPhoto(day: model.clock.today, pose: "front", imageData: jpeg, createdAt: model.clock.now))
        try? context.save()
        pickedPhoto = nil
    }

    static func summary(_ entry: BodyMeasurement) -> String {
        let parts: [(String, Double?)] = [
            ("Taille", entry.waistCm), ("Hanches", entry.hipsCm), ("Poitrine", entry.chestCm),
            ("Bras", entry.armCm), ("Cuisse", entry.thighCm),
        ]
        return parts.compactMap { label, value in value.map { "\(label) \(Format.number($0)) cm" } }.joined(separator: " · ")
    }
}

/// Saisie des mensurations du jour.
private struct MeasurementEditView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var values = ["", "", "", "", ""]
    private let labels = ["Tour de taille", "Hanches", "Poitrine", "Bras", "Cuisse"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(labels.indices, id: \.self) { index in
                        LabeledContent("\(labels[index]) (cm)") {
                            TextField("—", text: $values[index])
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .accessibilityIdentifier("measure-\(index)")
                        }
                    }
                } footer: {
                    ListFooter {
                        Text("Remplis seulement ce que tu mesures.")
                    }
                }
            }
            .themedList()
            .navigationTitle("Mensurations")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer", action: save)
                        .disabled(values.allSatisfy { parse($0) == nil })
                        .accessibilityIdentifier("saveMeasurement")
                }
            }
        }
    }

    private func parse(_ text: String) -> Double? {
        Format.parse(text).flatMap { (10...250).contains($0) ? $0 : nil }
    }

    private func save() {
        let entry = BodyMeasurement(day: model.clock.today, recordedAt: model.clock.now)
        entry.waistCm = parse(values[0])
        entry.hipsCm = parse(values[1])
        entry.chestCm = parse(values[2])
        entry.armCm = parse(values[3])
        entry.thighCm = parse(values[4])
        context.insert(entry)
        try? context.save()
        dismiss()
    }
}

extension UIImage {
    /// Image réduite pour que son plus grand côté fasse au plus `maxSide` points.
    func scaled(maxSide: CGFloat) -> UIImage {
        let ratio = min(1, maxSide / max(size.width, size.height))
        guard ratio < 1 else { return self }
        let target = CGSize(width: size.width * ratio, height: size.height * ratio)
        return UIGraphicsImageRenderer(size: target).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
    }
}
