import Testing
@testable import CodexMeterCore

@Suite("CodexQuotaParser")
struct CodexQuotaParserTests {
    @Test("only weekly window")
    func weeklyOnlyWindow() throws {
        let json = """
        {
          "rateLimits": {
            "primary": {
              "usedPercent": 32,
              "windowDurationMins": 10080,
              "resetsAt": 1787205408
            }
          }
        }
        """
        let snapshot = try CodexQuotaParser.parseRateLimits(json: json)
        #expect(snapshot.usedPercent == 32)
        #expect(snapshot.remainingPercent == 68)
        #expect(snapshot.windowMinutes == 10080)
        #expect(snapshot.resetAt?.timeIntervalSince1970 == 1_787_205_408)
    }

    @Test("prefers weekly over 5-hour window")
    func prefersWeeklyOverFiveHourWindow() throws {
        let json = """
        {
          "rateLimits": {
            "primary": {
              "usedPercent": 80,
              "windowDurationMins": 300,
              "resetsAt": 1786617000
            },
            "secondary": {
              "usedPercent": 32,
              "windowDurationMins": 10080,
              "resetsAt": 1787205408
            }
          }
        }
        """
        let snapshot = try CodexQuotaParser.parseRateLimits(json: json)
        #expect(snapshot.windowMinutes == 10080)
        #expect(snapshot.usedPercent == 32)
        #expect(snapshot.remainingPercent == 68)
    }

    @Test("weekly in primary")
    func weeklyInPrimary() throws {
        let json = """
        {
          "rateLimits": {
            "primary": {
              "usedPercent": 12,
              "windowDurationMins": 10080,
              "resetsAt": 1787205408
            },
            "secondary": {
              "usedPercent": 44,
              "windowDurationMins": 300
            }
          }
        }
        """
        let snapshot = try CodexQuotaParser.parseRateLimits(json: json)
        #expect(snapshot.usedPercent == 12)
        #expect(snapshot.remainingPercent == 88)
    }

    @Test("weekly in secondary")
    func weeklyInSecondary() throws {
        let json = """
        {
          "rateLimits": {
            "primary": {
              "usedPercent": 91,
              "windowDurationMins": 300
            },
            "secondary": {
              "usedPercent": 55,
              "windowDurationMins": 10080
            }
          }
        }
        """
        let snapshot = try CodexQuotaParser.parseRateLimits(json: json)
        #expect(snapshot.windowMinutes == 10080)
        #expect(snapshot.usedPercent == 55)
        #expect(snapshot.remainingPercent == 45)
    }

    @Test("missing resetAt does not crash")
    func missingResetAtDoesNotCrash() throws {
        let json = """
        {
          "rateLimits": {
            "primary": {
              "usedPercent": 20,
              "windowDurationMins": 10080
            }
          }
        }
        """
        let snapshot = try CodexQuotaParser.parseRateLimits(json: json)
        #expect(snapshot.resetAt == nil)
        #expect(snapshot.remainingPercent == 80)
    }

    @Test("unknown fields are ignored")
    func unknownFieldsAreIgnored() throws {
        let json = """
        {
          "rateLimits": {
            "limitId": "codex",
            "brandNewField": {"nested": true},
            "primary": {
              "usedPercent": 4,
              "windowDurationMins": 10080,
              "resetsAt": 1787205408,
              "mystery": "ok"
            }
          },
          "futureArray": [1, 2, 3]
        }
        """
        let snapshot = try CodexQuotaParser.parseRateLimits(json: json)
        #expect(snapshot.usedPercent == 4)
        #expect(snapshot.remainingPercent == 96)
        #expect(snapshot.limitId == "codex")
    }

    @Test("usedPercent above 100 is clamped")
    func usedPercentAbove100IsClamped() throws {
        let json = """
        {
          "rateLimits": {
            "primary": {
              "usedPercent": 150,
              "windowDurationMins": 10080
            }
          }
        }
        """
        let snapshot = try CodexQuotaParser.parseRateLimits(json: json)
        #expect(snapshot.usedPercent == 100)
        #expect(snapshot.remainingPercent == 0)
    }

    @Test("usedPercent below 0 is clamped")
    func usedPercentBelowZeroIsClamped() throws {
        let json = """
        {
          "rateLimits": {
            "primary": {
              "usedPercent": -10,
              "windowDurationMins": 10080
            }
          }
        }
        """
        let snapshot = try CodexQuotaParser.parseRateLimits(json: json)
        #expect(snapshot.usedPercent == 0)
        #expect(snapshot.remainingPercent == 100)
    }

    @Test("snake_case window minutes")
    func snakeCaseWindowMinutes() throws {
        let json = """
        {
          "rate_limits": {
            "secondary": {
              "used_percent": 40,
              "window_minutes": 10080,
              "resets_at": 1787205408
            }
          }
        }
        """
        let snapshot = try CodexQuotaParser.parseRateLimits(json: json)
        #expect(snapshot.usedPercent == 40)
        #expect(snapshot.remainingPercent == 60)
        #expect(snapshot.resetAt != nil)
    }

    @Test("weekly in rateLimitsByLimitId")
    func weeklyInRateLimitsByLimitId() throws {
        let json = """
        {
          "rateLimits": {
            "primary": {
              "usedPercent": 99,
              "windowDurationMins": 300
            }
          },
          "rateLimitsByLimitId": {
            "codex": {
              "limitId": "codex",
              "planType": "plus",
              "primary": {
                "usedPercent": 4,
                "windowDurationMins": 10080,
                "resetsAt": 1787205408
              }
            }
          }
        }
        """
        let snapshot = try CodexQuotaParser.parseRateLimits(json: json)
        #expect(snapshot.usedPercent == 4)
        #expect(snapshot.planType == "plus")
    }

    @Test("missing usedPercent falls back to remaining")
    func missingUsedPercentFallsBackToRemaining() throws {
        let json = """
        {
          "rateLimits": {
            "primary": {
              "remainingPercent": 72,
              "windowDurationMins": 10080
            }
          }
        }
        """
        let snapshot = try CodexQuotaParser.parseRateLimits(json: json)
        #expect(snapshot.remainingPercent == 72)
        #expect(snapshot.usedPercent == 28)
    }
}
