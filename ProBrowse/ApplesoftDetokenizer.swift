//
//  ApplesoftDetokenizer.swift
//  ProBrowse
//
//  Converts tokenized Applesoft BASIC programs to readable text
//

import Foundation

class ApplesoftDetokenizer {

    // Complete Applesoft BASIC token table ($80-$EA)
    static let tokens: [UInt8: String] = [
        // Statement tokens ($80-$BF)
        0x80: "END",
        0x81: "FOR",
        0x82: "NEXT",
        0x83: "DATA",
        0x84: "INPUT",
        0x85: "DEL",
        0x86: "DIM",
        0x87: "READ",
        0x88: "GR",
        0x89: "TEXT",
        0x8A: "PR#",
        0x8B: "IN#",
        0x8C: "CALL",
        0x8D: "PLOT",
        0x8E: "HLIN",
        0x8F: "VLIN",
        0x90: "HGR2",
        0x91: "HGR",
        0x92: "HCOLOR=",
        0x93: "HPLOT",
        0x94: "DRAW",
        0x95: "XDRAW",
        0x96: "HTAB",
        0x97: "HOME",
        0x98: "ROT=",
        0x99: "SCALE=",
        0x9A: "SHLOAD",
        0x9B: "TRACE",
        0x9C: "NOTRACE",
        0x9D: "NORMAL",
        0x9E: "INVERSE",
        0x9F: "FLASH",
        0xA0: "COLOR=",
        0xA1: "POP",
        0xA2: "VTAB",
        0xA3: "HIMEM:",
        0xA4: "LOMEM:",
        0xA5: "ONERR",
        0xA6: "RESUME",
        0xA7: "RECALL",
        0xA8: "STORE",
        0xA9: "SPEED=",
        0xAA: "LET",
        0xAB: "GOTO",
        0xAC: "RUN",
        0xAD: "IF",
        0xAE: "RESTORE",
        0xAF: "&",
        0xB0: "GOSUB",
        0xB1: "RETURN",
        0xB2: "REM",
        0xB3: "STOP",
        0xB4: "ON",
        0xB5: "WAIT",
        0xB6: "LOAD",
        0xB7: "SAVE",
        0xB8: "DEF",
        0xB9: "POKE",
        0xBA: "PRINT",
        0xBB: "CONT",
        0xBC: "LIST",
        0xBD: "CLEAR",
        0xBE: "GET",
        0xBF: "NEW",

        // Operator/function tokens ($C0-$EA)
        0xC0: "TAB(",
        0xC1: "TO",
        0xC2: "FN",
        0xC3: "SPC(",
        0xC4: "THEN",
        0xC5: "AT",
        0xC6: "NOT",
        0xC7: "STEP",
        0xC8: "+",
        0xC9: "-",
        0xCA: "*",
        0xCB: "/",
        0xCC: "^",
        0xCD: "AND",
        0xCE: "OR",
        0xCF: ">",
        0xD0: "=",
        0xD1: "<",
        0xD2: "SGN",
        0xD3: "INT",
        0xD4: "ABS",
        0xD5: "USR",
        0xD6: "FRE",
        0xD7: "SCRN(",
        0xD8: "PDL",
        0xD9: "POS",
        0xDA: "SQR",
        0xDB: "RND",
        0xDC: "LOG",
        0xDD: "EXP",
        0xDE: "COS",
        0xDF: "SIN",
        0xE0: "TAN",
        0xE1: "ATN",
        0xE2: "PEEK",
        0xE3: "LEN",
        0xE4: "STR$",
        0xE5: "VAL",
        0xE6: "ASC",
        0xE7: "CHR$",
        0xE8: "LEFT$",
        0xE9: "RIGHT$",
        0xEA: "MID$"
    ]

    /// Detokenize an Applesoft BASIC program
    /// - Parameter data: Raw tokenized BASIC data
    /// - Returns: Human-readable BASIC listing
    static func detokenize(_ data: Data) -> String {
        guard data.count >= 2 else {
            return "// Invalid BASIC program (too short)"
        }

        var result = ""
        var pos = 0

        // Applesoft programs start with a 2-byte pointer to the next line
        // The actual program data follows
        while pos + 4 <= data.count {
            // Read next line pointer (2 bytes, little-endian)
            let nextLinePtrLow = Int(data[pos])
            let nextLinePtrHigh = Int(data[pos + 1])
            let nextLinePtr = nextLinePtrLow | (nextLinePtrHigh << 8)

            // End of program marker
            if nextLinePtr == 0 {
                break
            }

            pos += 2

            // Check if we have enough data for line number
            guard pos + 2 <= data.count else { break }

            // Read line number (2 bytes, little-endian)
            let lineNumLow = Int(data[pos])
            let lineNumHigh = Int(data[pos + 1])
            let lineNumber = lineNumLow | (lineNumHigh << 8)

            pos += 2

            // Format line number with padding
            result += String(format: "%5d ", lineNumber)

            // Process line content until null terminator
            var inQuote = false
            var inREM = false
            var inDATA = false

            while pos < data.count {
                let byte = data[pos]
                pos += 1

                // End of line
                if byte == 0x00 {
                    break
                }

                if inQuote {
                    // Inside quotes: treat all bytes as literal characters
                    if byte == 0x22 {  // End quote
                        inQuote = false
                        result += "\""
                    } else {
                        // Convert to printable ASCII
                        let printable = byte & 0x7F
                        if printable >= 0x20 && printable < 0x7F {
                            result += String(UnicodeScalar(printable))
                        } else {
                            result += "."
                        }
                    }
                } else if inREM {
                    // Inside REM: everything is literal until end of line
                    let printable = byte & 0x7F
                    if printable >= 0x20 && printable < 0x7F {
                        result += String(UnicodeScalar(printable))
                    } else if byte >= 0x80 {
                        // High-ASCII character
                        result += String(UnicodeScalar(printable))
                    } else {
                        result += "."
                    }
                } else if inDATA {
                    // Inside DATA: tokens are not expanded, but colons end DATA
                    if byte == 0x3A {  // Colon ends DATA statement
                        inDATA = false
                        result += ":"
                    } else if byte == 0x22 {
                        inQuote = true
                        result += "\""
                    } else {
                        let printable = byte & 0x7F
                        if printable >= 0x20 && printable < 0x7F {
                            result += String(UnicodeScalar(printable))
                        }
                    }
                } else if byte >= 0x80 {
                    // Token
                    if let token = tokens[byte] {
                        // Operators that need space before and after
                        let comparisonOps: Set<String> = ["=", "<", ">", "AND", "OR", "NOT"]
                        let mathOps: Set<String> = ["+", "-", "*", "/", "^"]

                        // Add space before token if needed
                        if let lastChar = result.last {
                            if comparisonOps.contains(token) {
                                // Always add space before comparison operators (unless already space)
                                if lastChar != " " && lastChar != "(" {
                                    result += " "
                                }
                            } else if (lastChar.isLetter || lastChar.isNumber) {
                                // Don't add space before math ops, parens, comma, semicolon
                                let noSpaceBefore: Set<String> = ["+", "-", "*", "/", "^", "(", ")", ",", ";"]
                                if !noSpaceBefore.contains(token) && !token.hasSuffix("(") && !token.hasSuffix("=") && !token.hasSuffix(":") {
                                    result += " "
                                }
                            }
                        }

                        result += token

                        // Add space after comparison operators
                        if comparisonOps.contains(token) {
                            result += " "
                        }

                        // Add space after certain statement tokens
                        let needsSpaceAfter: Set<String> = [
                            "GOTO", "GOSUB", "THEN", "IF", "FOR", "NEXT", "TO", "STEP",
                            "LET", "DIM", "DEF", "ON", "PRINT", "INPUT", "READ", "DATA",
                            "POKE", "CALL", "HTAB", "VTAB", "HCOLOR=", "COLOR=", "SPEED=",
                            "HPLOT", "PLOT", "DRAW", "XDRAW", "AT", "ONERR", "RESUME",
                            "HIMEM:", "LOMEM:", "WAIT", "GET", "HOME", "TEXT", "GR", "HGR", "HGR2",
                            "LOAD", "SAVE", "DEL", "RUN", "LIST", "ROT=", "SCALE=", "PR#", "IN#"
                        ]
                        if needsSpaceAfter.contains(token) {
                            result += " "
                        }
                        if token == "REM" {
                            inREM = true
                        } else if token == "DATA" {
                            inDATA = true
                        }
                    } else {
                        // Unknown token
                        result += "[?\(String(format: "%02X", byte))]"
                    }
                } else if byte == 0x22 {
                    // Start quote
                    inQuote = true
                    result += "\""
                } else if byte == 0x3A {
                    // Colon - statement separator, add spaces around it
                    result += " : "
                } else if byte >= 0x20 && byte < 0x7F {
                    // Regular printable ASCII
                    result += String(UnicodeScalar(byte))
                } else if byte == 0x0D {
                    // Carriage return (shouldn't appear but handle it)
                    result += "\n"
                }
            }

            result += "\n"
        }

        if result.isEmpty {
            return "// Unable to detokenize BASIC program"
        }

        return result
    }

    /// Check if data appears to be a valid Applesoft BASIC program
    /// - Parameter data: Data to check
    /// - Returns: true if it looks like Applesoft BASIC
    static func isValidBasicProgram(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }

        // First two bytes should be a valid pointer
        let nextLinePtr = Int(data[0]) | (Int(data[1]) << 8)

        // Should be a reasonable address (usually $0801 to $9600 range)
        if nextLinePtr < 0x0800 || nextLinePtr > 0xC000 {
            return false
        }

        // Line number should be reasonable (0-63999)
        let lineNumber = Int(data[2]) | (Int(data[3]) << 8)
        if lineNumber > 63999 {
            return false
        }

        return true
    }
}

/// Integer BASIC detokenizer (for type $FA files)
class IntegerBasicDetokenizer {

    // Integer BASIC token table
    static let tokens: [UInt8: String] = [
        0x00: "HIMEM:",
        0x01: "_",  // Placeholder
        0x02: "_",
        0x03: ":",
        0x04: "LOAD",
        0x05: "SAVE",
        0x06: "CON",
        0x07: "RUN",
        0x08: "RUN",
        0x09: "DEL",
        0x0A: ",",
        0x0B: "NEW",
        0x0C: "CLR",
        0x0D: "AUTO",
        0x0E: ",",
        0x0F: "MAN",
        0x10: "HIMEM:",
        0x11: "LOMEM:",
        0x12: "+",
        0x13: "-",
        0x14: "*",
        0x15: "/",
        0x16: "=",
        0x17: "#",
        0x18: ">=",
        0x19: ">",
        0x1A: "<=",
        0x1B: "<>",
        0x1C: "<",
        0x1D: "AND",
        0x1E: "OR",
        0x1F: "MOD",
        0x20: "^",
        0x21: "+",  // Unary plus
        0x22: "(",
        0x23: ",",
        0x24: "THEN",
        0x25: "THEN",
        0x26: ",",
        0x27: ",",
        0x28: "\"",
        0x29: "\"",
        0x2A: "(",
        0x2B: "!",  // Exclamation (comment)
        0x2C: "!",
        0x2D: "(",
        0x2E: "PEEK",
        0x2F: "RND",
        0x30: "SGN",
        0x31: "ABS",
        0x32: "PDL",
        0x33: "RNDX",
        0x34: "(",
        0x35: "+",
        0x36: "-",
        0x37: "NOT",
        0x38: "(",
        0x39: "=",
        0x3A: "#",
        0x3B: "LEN(",
        0x3C: "ASC(",
        0x3D: "SCRN(",
        0x3E: ",",
        0x3F: "(",
        0x40: "$",
        0x41: "$",
        0x42: "(",
        0x43: ",",
        0x44: ",",
        0x45: ";",
        0x46: ";",
        0x47: ";",
        0x48: ",",
        0x49: ",",
        0x4A: ",",
        0x4B: "TEXT",
        0x4C: "GR",
        0x4D: "CALL",
        0x4E: "DIM",
        0x4F: "DIM",
        0x50: "TAB",
        0x51: "END",
        0x52: "INPUT",
        0x53: "INPUT",
        0x54: "INPUT",
        0x55: "FOR",
        0x56: "=",
        0x57: "TO",
        0x58: "STEP",
        0x59: "NEXT",
        0x5A: ",",
        0x5B: "RETURN",
        0x5C: "GOSUB",
        0x5D: "REM",
        0x5E: "LET",
        0x5F: "GOTO",
        0x60: "IF",
        0x61: "PRINT",
        0x62: "PRINT",
        0x63: "PRINT",
        0x64: "POKE",
        0x65: ",",
        0x66: "COLOR=",
        0x67: "PLOT",
        0x68: ",",
        0x69: "HLIN",
        0x6A: ",",
        0x6B: "AT",
        0x6C: "VLIN",
        0x6D: ",",
        0x6E: "AT",
        0x6F: "VTAB",
        0x70: "=",
        0x71: "=",
        0x72: ")",
        0x73: ")",
        0x74: "LIST",
        0x75: ",",
        0x76: "LIST",
        0x77: "POP",
        0x78: "NODSP",
        0x79: "NODSP",
        0x7A: "NOTRACE",
        0x7B: "DSP",
        0x7C: "DSP",
        0x7D: "TRACE",
        0x7E: "PR#",
        0x7F: "IN#"
    ]

    /// Detokenize an Integer BASIC program
    static func detokenize(_ data: Data) -> String {
        // Integer BASIC format is different from Applesoft
        // This is a simplified implementation
        guard data.count >= 2 else {
            return "// Invalid Integer BASIC program"
        }

        var result = "// Integer BASIC program\n"
        result += "// (Full detokenization not yet implemented)\n\n"

        // For now, show a hex dump preview
        let previewBytes = min(data.count, 64)
        for i in 0..<previewBytes {
            result += String(format: "%02X ", data[i])
            if (i + 1) % 16 == 0 {
                result += "\n"
            }
        }

        return result
    }
}
