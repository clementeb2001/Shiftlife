import SwiftUI
import CoreLocation

/// Smart Shift Detection settings (#3): work locations + auto-detect, plus a
/// manual "simulate" trigger so the overtime → handover flow is testable now.
struct WorkplacesView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var monitor = LocationMonitor.shared
    @State private var detection: DetectionTarget?
    @State private var capturing = false

    struct DetectionTarget: Identifiable {
        let id = UUID()
        let instanceID: UUID
        let detectedEndMinutes: Int
    }

    var body: some View {
        List {
            Section {
                Toggle("Automatische Erkennung", isOn: autoBinding)
            } footer: {
                Text(monitor.authorized
                     ? "ShiftLife nutzt Geofencing rund um geplante Dienste, um ein späteres Dienstende zu erkennen. Standort wird lokal verarbeitet."
                     : "Für die Erkennung wird Standortzugriff benötigt. Erst beim Aktivieren fragt iOS danach.")
            }

            Section {
                if store.data.workplaces.isEmpty {
                    Text("Noch kein Arbeitsort gespeichert.").foregroundStyle(Theme.subtleText)
                }
                ForEach(store.data.workplaces) { w in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(w.name).fontWeight(.medium)
                        Text(String(format: "%.4f, %.4f · Radius %.0f m", w.latitude, w.longitude, w.radiusMeters))
                            .font(.caption).foregroundStyle(Theme.subtleText)
                    }
                }
                .onDelete { store.data.workplaces.remove(atOffsets: $0) }

                Button {
                    captureLocation()
                } label: {
                    Label(capturing ? "Standort wird ermittelt …" : "Aktuellen Standort als Arbeitsort",
                          systemImage: "mappin.and.ellipse")
                }
                .disabled(capturing)
            } header: { Text("Arbeitsorte") }
            footer: { Text("Tipp: einmal am Arbeitsplatz speichern. Auf diesem Simulator/ohne Standort bleibt die Liste leer.") }

            Section {
                Button {
                    simulate()
                } label: {
                    Label("Erkennung simulieren (Test)", systemImage: "wand.and.stars")
                }
            } footer: {
                Text("Simuliert ein um 1 Std 20 späteres Verlassen des Arbeitsplatzes für deinen heutigen bzw. nächsten Dienst – inkl. Überzeit und Smart Handover.")
            }
        }
        .navigationTitle("Arbeitsorte & Erkennung")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $detection) { d in
            OvertimeDetectionSheet(instanceID: d.instanceID, detectedEndMinutes: d.detectedEndMinutes)
        }
    }

    private var autoBinding: Binding<Bool> {
        Binding(
            get: { store.data.autoDetectEnabled },
            set: { on in
                store.data.autoDetectEnabled = on
                if on {
                    monitor.requestAuthorization()
                    monitor.startMonitoring(store.data.workplaces)
                } else {
                    monitor.stopAll()
                }
            }
        )
    }

    private func captureLocation() {
        capturing = true
        monitor.requestAuthorization()
        monitor.captureCurrent { coord in
            DispatchQueue.main.async {
                capturing = false
                guard let coord else { return }
                let n = store.data.workplaces.count + 1
                store.data.workplaces.append(
                    Workplace(name: "Arbeitsort \(n)", latitude: coord.latitude, longitude: coord.longitude))
                if store.data.autoDetectEnabled { monitor.startMonitoring(store.data.workplaces) }
            }
        }
    }

    private func simulate() {
        let user = store.currentUser
        let inst = store.shiftInstance(for: user.id, on: Calendar.current.startOfDay(for: Date()))
            ?? store.nextShift(for: user.id)
        guard let inst else { return }
        let planned = store.effectiveMinutes(inst).end
        detection = DetectionTarget(instanceID: inst.id, detectedEndMinutes: (planned + 80) % (24 * 60))
    }
}

/// Two-step flow: confirm a detected later end (#3), then optionally hand over
/// affected childcare/appointments to the partner (#9).
struct OvertimeDetectionSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let instanceID: UUID
    let detectedEndMinutes: Int

    private enum Phase { case detect, handover }
    @State private var phase: Phase = .detect

    private var inst: ShiftInstance? { store.data.shiftInstances.first { $0.id == instanceID } }
    private var partner: HouseholdMember? { store.data.members.first { $0.role == .partner } }
    private var partnerName: String {
        guard let p = partner else { return "Partner" }
        return p.name.split(separator: " ").first.map(String.init) ?? p.name
    }

    var body: some View {
        NavigationStack {
            Group {
                if let inst, let t = store.shiftType(inst.shiftTypeID) {
                    switch phase {
                    case .detect: detectView(inst, t)
                    case .handover: handoverView(inst)
                    }
                } else {
                    Text("Kein Dienst gefunden.").foregroundStyle(Theme.subtleText)
                }
            }
            .navigationTitle(phase == .detect ? "Verlängerung erkannt" : "Haushalt anpassen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func detectView(_ inst: ShiftInstance, _ t: ShiftType) -> some View {
        let planned = store.effectiveMinutes(inst).end
        var over = detectedEndMinutes - planned; if over < 0 { over += 24 * 60 }
        return List {
            Section {
                Text("Du hast den Arbeitsplatz nach dem geplanten Ende von \(t.name) verlassen.")
                    .font(.subheadline)
                LabeledContent("Geplantes Ende", value: ShiftType.timeString(planned))
                LabeledContent("Erkanntes Ende", value: ShiftType.timeString(detectedEndMinutes))
                LabeledContent("Überzeit", value: "+\(over / 60):\(String(format: "%02d", over % 60))")
            }
            Section {
                Button {
                    store.applyDetectedEnd(instanceID: instanceID, newEndMinutes: detectedEndMinutes)
                    if partner != nil, !store.handoverCandidates(for: inst).isEmpty {
                        phase = .handover
                    } else {
                        dismiss()
                    }
                } label: { Label("Verlängerung übernehmen", systemImage: "checkmark.circle.fill") }
                Button(role: .cancel) { dismiss() } label: { Text("Ignorieren") }
            } footer: {
                Text("Übernehmen aktualisiert Dienstende & Überzeit und prüft betroffene Betreuung/Termine (Smart Handover).")
            }
        }
    }

    private func handoverView(_ inst: ShiftInstance) -> some View {
        let affected = store.handoverCandidates(for: inst)
        return List {
            Section {
                Text("Dein Dienst endet jetzt später. Diese Punkte überschneiden sich – an \(partnerName) übertragen?")
                    .font(.subheadline)
            }
            Section {
                if affected.isEmpty {
                    Label("Nichts mehr offen.", systemImage: "checkmark.seal.fill").foregroundStyle(Theme.success)
                }
                ForEach(affected) { ev in
                    HStack {
                        Image(systemName: ev.category.systemImage).foregroundStyle(Theme.brand)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(ev.title).fontWeight(.medium)
                            Text("\(Format.relativeDay(ev.start)) · \(Format.time(ev.start))")
                                .font(.caption).foregroundStyle(Theme.subtleText)
                        }
                        Spacer()
                        if let p = partner {
                            Button {
                                store.reassignEvent(ev, to: p.id)
                            } label: {
                                Text("→ \(p.name.split(separator: " ").first.map(String.init) ?? p.name)")
                                    .font(.caption).fontWeight(.medium)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(Theme.brand.opacity(0.12), in: Capsule())
                                    .foregroundStyle(Theme.brand)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            Section {
                Button { dismiss() } label: { Text("Fertig") }
            }
        }
    }
}
