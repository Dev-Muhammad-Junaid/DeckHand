//
//  StoreFreeMacTests.swift
//  PixelHandCoreTests
//
//  The free plan's one-Mac rule and the subscription copy (status row and
//  the guideline 3.1.2 disclosure).
//

import Foundation
import PixelHandCore
import Testing

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private let day: TimeInterval = 24 * 60 * 60
private let studio = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!
private let laptop = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000002")!

@Suite("Store one-Mac rule")
struct StoreFreeMacTests {
    @Test("The first Mac becomes the free Mac, picked automatically")
    func firstMac() {
        let result = FreeMacPolicy.admit(deviceID: studio, name: "Studio", isPro: false, choice: nil, now: now)
        #expect(result == .allowed(choice: FreeMacChoice(deviceID: studio, name: "Studio")))
    }

    @Test("The free Mac is always allowed, and its new name is remembered")
    func sameMac() {
        let choice = FreeMacChoice(deviceID: studio, name: "Studio", changedByUserAt: now)
        let result = FreeMacPolicy.admit(deviceID: studio, name: "Studio 2", isPro: false, choice: choice, now: now)
        #expect(result == .allowed(choice: FreeMacChoice(deviceID: studio, name: "Studio 2", changedByUserAt: now)))
    }

    @Test("Without Pro, a second Mac needs Pro; an automatic pick can change at once")
    func secondMacFree() {
        let auto = FreeMacChoice(deviceID: studio, name: "Studio")
        let result = FreeMacPolicy.admit(deviceID: laptop, name: "Laptop", isPro: false, choice: auto, now: now)
        #expect(result == .needsPro(freeMac: auto, switchAllowedAt: .distantPast))
    }

    @Test("With Pro, any Mac is allowed and the free Mac follows the last one used")
    func secondMacPro() {
        let mine = FreeMacChoice(deviceID: studio, name: "Studio", changedByUserAt: now)
        let result = FreeMacPolicy.admit(deviceID: laptop, name: "Laptop", isPro: true, choice: mine, now: now)
        #expect(result == .allowed(choice: FreeMacChoice(deviceID: laptop, name: "Laptop")))
    }

    @Test("A change you make waits 7 days for the next one")
    func switchCooldown() {
        let auto = FreeMacChoice(deviceID: studio, name: "Studio")
        let switched = FreeMacPolicy.switchFreeMac(to: laptop, name: "Laptop", from: auto, now: now)
        #expect(switched == FreeMacChoice(deviceID: laptop, name: "Laptop", changedByUserAt: now))

        let soon = FreeMacPolicy.switchFreeMac(to: studio, name: "Studio", from: switched, now: now.addingTimeInterval(6 * day))
        #expect(soon == nil)
        let blocked = FreeMacPolicy.admit(deviceID: studio, name: "Studio", isPro: false, choice: switched, now: now.addingTimeInterval(day))
        #expect(blocked == .needsPro(freeMac: switched!, switchAllowedAt: now.addingTimeInterval(7 * day)))

        let later = FreeMacPolicy.switchFreeMac(to: studio, name: "Studio", from: switched, now: now.addingTimeInterval(7 * day))
        #expect(later?.deviceID == studio)
    }

    @Test("Setting the clock back before the last change doesn't allow a change")
    func clockBack() {
        let mine = FreeMacChoice(deviceID: studio, name: "Studio", changedByUserAt: now)
        #expect(FreeMacPolicy.switchFreeMac(to: laptop, name: "Laptop", from: mine, now: now.addingTimeInterval(-30 * day)) == nil)
    }

    @Test("Choosing with nothing recorded always works")
    func switchFromNothing() {
        #expect(FreeMacPolicy.switchFreeMac(to: laptop, name: "Laptop", from: nil, now: now)?.deviceID == laptop)
    }

    @Test("The choice survives a JSON round trip")
    func codable() throws {
        let choice = FreeMacChoice(deviceID: studio, name: "Studio", changedByUserAt: now)
        let data = try JSONEncoder().encode(choice)
        #expect(try JSONDecoder().decode(FreeMacChoice.self, from: data) == choice)
    }
}

@Suite("Store copy")
struct StoreCopyTests {
    private let format: (Date) -> String = { date in
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    @Test("The disclosure names prices, periods, the trial, auto-renewal and cancelling")
    func disclosure() {
        let text = SubscriptionCopy.disclosure(monthlyPrice: "$2.99", yearlyPrice: "$19.99", trialEligible: true)
        for required in ["$2.99 per month", "$19.99 per year", "auto-renewable", "2-week free trial", "renews automatically", "24 hours", "cancel", "Apple Account"] {
            #expect(text.contains(required), "missing \(required)")
        }
        let noTrial = SubscriptionCopy.disclosure(monthlyPrice: nil, yearlyPrice: nil, trialEligible: false)
        #expect(!noTrial.contains("free trial"))
        #expect(noTrial.contains("$2.99 per month"))
    }

    @Test("Plan captions lead with the billed price and the trial")
    func planCaption() {
        #expect(SubscriptionCopy.billedPrice(.yearly, displayPrice: "19,99 €") == "19,99 € / year")
        #expect(SubscriptionCopy.planCaption(.yearly, displayPrice: "$19.99", trialEligible: true, savingsPercent: 44) == "2 weeks free, then $19.99 per year · save 44%")
        #expect(SubscriptionCopy.planCaption(.monthly, displayPrice: nil, trialEligible: false, savingsPercent: 44) == "$2.99 per month")
    }

    @Test("Status rows for each state")
    func statusRows() {
        let end = now.addingTimeInterval(14 * day)
        func row(_ status: Entitlement.Status) -> SubscriptionCopy.StatusRow {
            SubscriptionCopy.statusRow(Entitlement(status: status, evaluatedAt: now), formatDate: format)
        }
        #expect(row(.notSubscribed).title == "Free plan")
        #expect(row(.trial(plan: .monthly, endsOn: end, willRenew: true)).detail == "Free until 2027-01-29, then $2.99/month.")
        #expect(row(.trial(plan: .monthly, endsOn: end, willRenew: false)).detail == "Trial ends 2027-01-29. It won't renew.")
        #expect(row(.active(plan: .yearly, periodEnds: end, willRenew: true, renewsTo: nil, familyShared: false)) == .init(title: "Pixel Hand Pro, yearly", detail: "Renews 2027-01-29 at $19.99/year."))
        #expect(row(.active(plan: .monthly, periodEnds: end, willRenew: true, renewsTo: .yearly, familyShared: true)).detail == "Shared by your family. Switches to yearly on 2027-01-29.")
        #expect(row(.gracePeriod(plan: .monthly, until: end)).needsPaymentAttention)
        #expect(row(.billingRetry(plan: .monthly)).needsPaymentAttention)
        #expect(row(.expired(on: now)).detail == "Pro ended 2027-01-15. You're on the free plan.")
        #expect(row(.revoked).title == "Free plan")
    }

    @Test("Headlines name the locked feature")
    func headlines() {
        #expect(SubscriptionCopy.headline(for: .mirror) == "Live mirror is part of Pixel Hand Pro")
        #expect(SubscriptionCopy.headline(for: .multipleMacs) == "Control all your Macs")
        #expect(SubscriptionCopy.headline(for: nil) == "Get more from Pixel Hand")
        #expect(SubscriptionCopy.headline(for: .trackpad) == "Get more from Pixel Hand")
        #expect(SubscriptionCopy.termsOfUseURL.absoluteString.hasPrefix("https://www.apple.com/legal/"))
        #expect(SubscriptionCopy.privacyPolicyURL.absoluteString == "https://pixelhand.app/privacy")
    }
}
