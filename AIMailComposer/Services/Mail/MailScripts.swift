import Foundation

enum MailScripts {
    /// Read context from the currently open compose window in Mail.
    ///
    /// This script is implemented entirely against the Mail scripting
    /// dictionary — no System Events / Accessibility calls — so on its own
    /// it only needs Automation permission for Mail. That guarantee no
    /// longer holds for the app as a whole: when this path comes back
    /// empty on recent macOS versions, `MailBridge` augments the result
    /// via the Accessibility reader (`AccessibilityReader`). That widens
    /// the permission footprint — AX can read every app's UI — which is a
    /// deliberate trade-off recorded here rather than left as silent
    /// comment rot.
    ///
    /// Detection priority:
    ///   1. `outgoing message 1` properties (best: gives recipients + draft)
    ///   2. Any Mail `window` that is not the `message viewer`'s window (the
    ///      list/reading pane). This covers the case on newer macOS releases
    ///      where a brand-new blank compose window doesn't show up in
    ///      `outgoing messages`.
    static let fetchComposerContext = """
    set composeSubject to ""
    set recipientList to ""
    set draftContent to ""
    set composeWinL to "-"
    set composeWinT to "-"
    set composeWinR to "-"
    set composeWinB to "-"
    set hasComposer to false
    set debugInfo to ""

    tell application "Mail"
        -- Pass 1: outgoing message. Populates everything.
        try
            set outMsgCount to count of outgoing messages
            set debugInfo to "out:" & outMsgCount
            if outMsgCount > 0 then
                set outMsg to outgoing message 1
                try
                    set composeSubject to subject of outMsg
                end try
                try
                    repeat with r in to recipients of outMsg
                        if recipientList is not "" then set recipientList to recipientList & ", "
                        set recipientList to recipientList & (address of r)
                    end repeat
                end try
                try
                    set draftContent to content of outMsg
                end try
                set hasComposer to true
            end if
        on error errMsg
            set debugInfo to debugInfo & " outErr:" & errMsg
        end try

        -- Pass 2: find a non-viewer window. Works even for blank new
        -- compose windows that aren't exposed via `outgoing messages`.
        try
            set viewerNames to {}
            set viewerCount to count of message viewers
            set debugInfo to debugInfo & " vCount:" & viewerCount
            repeat with mv in message viewers
                try
                    set n to name of (window of mv)
                    set viewerNames to viewerNames & {n}
                end try
            end repeat

            set winCount to count of windows
            repeat with i from 1 to winCount
                try
                    set w to window i
                    set wName to name of w
                    set isViewer to false
                    repeat with vn in viewerNames
                        if wName is equal to (vn as string) then
                            set isViewer to true
                            exit repeat
                        end if
                    end repeat
                    if not isViewer then
                        -- Non-viewer window in Mail == compose (or reading)
                        -- window. Both are fine for our purposes.
                        if not hasComposer then
                            set composeSubject to wName
                            set hasComposer to true
                        end if
                        try
                            set b to bounds of w
                            set composeWinL to (item 1 of b) as string
                            set composeWinT to (item 2 of b) as string
                            set composeWinR to (item 3 of b) as string
                            set composeWinB to (item 4 of b) as string
                        end try
                        exit repeat
                    end if
                end try
            end repeat
        on error errMsg
            set debugInfo to debugInfo & " winErr:" & errMsg
        end try
    end tell

    if not hasComposer then
        return "ERROR:NO_COMPOSER|" & debugInfo
    end if

    -- Reply detection
    set isReply to false
    if composeSubject starts with "Re: " then set isReply to true
    if composeSubject starts with "Re:" then set isReply to true
    if composeSubject starts with "RE: " then set isReply to true
    if composeSubject starts with "RE:" then set isReply to true
    if composeSubject starts with "Fwd: " then set isReply to true
    if composeSubject starts with "Fwd:" then set isReply to true
    if composeSubject starts with "FWD: " then set isReply to true
    if composeSubject starts with "FWD:" then set isReply to true
    if composeSubject starts with "AW: " then set isReply to true
    if composeSubject starts with "AW:" then set isReply to true
    if composeSubject starts with "WG: " then set isReply to true
    if composeSubject starts with "WG:" then set isReply to true

    set output to "COMPOSER" & linefeed
    set output to output & "SUBJECT:" & composeSubject & linefeed
    set output to output & "TO:" & recipientList & linefeed
    set output to output & "FRAME:" & composeWinL & "," & composeWinT & "," & composeWinR & "," & composeWinB & linefeed
    set output to output & "DRAFT_START" & linefeed
    set output to output & draftContent & linefeed
    set output to output & "DRAFT_END" & linefeed
    set output to output & "---END_COMPOSER---" & linefeed

    if not isReply then
        return output
    end if

    set baseSubject to composeSubject
    set changed to true
    repeat while changed
        set changed to false
        if baseSubject starts with "Re: " then
            set baseSubject to text 5 thru -1 of baseSubject
            set changed to true
        else if baseSubject starts with "Re:" then
            set baseSubject to text 4 thru -1 of baseSubject
            set changed to true
        else if baseSubject starts with "RE: " then
            set baseSubject to text 5 thru -1 of baseSubject
            set changed to true
        else if baseSubject starts with "Fwd: " then
            set baseSubject to text 6 thru -1 of baseSubject
            set changed to true
        else if baseSubject starts with "Fwd:" then
            set baseSubject to text 5 thru -1 of baseSubject
            set changed to true
        else if baseSubject starts with "AW: " then
            set baseSubject to text 5 thru -1 of baseSubject
            set changed to true
        else if baseSubject starts with "WG: " then
            set baseSubject to text 5 thru -1 of baseSubject
            set changed to true
        end if
    end repeat

    if baseSubject is "" then
        return output
    end if

    tell application "Mail"
        set threadMsgs to {}
        try
            repeat with acct in accounts
                repeat with mbName in {"INBOX", "Sent Messages", "Sent", "Gesendet", "Archive", "Archiv", "All Mail"}
                    try
                        set mb to mailbox mbName of acct
                        set matches to (every message of mb whose subject contains baseSubject)
                        set threadMsgs to threadMsgs & matches
                    end try
                end repeat
            end repeat
        end try

        set msgCount to count of threadMsgs
        if msgCount > 20 then
            set threadMsgs to items (msgCount - 19) thru msgCount of threadMsgs
        end if

        repeat with msg in threadMsgs
            set output to output & "FROM:" & (sender of msg) & linefeed
            try
                set rList to ""
                repeat with r in to recipients of msg
                    if rList is not "" then set rList to rList & ", "
                    set rList to rList & (address of r)
                end repeat
                set output to output & "TO:" & rList & linefeed
            on error
                set output to output & "TO:unknown" & linefeed
            end try
            set output to output & "SUBJECT:" & (subject of msg) & linefeed
            try
                set output to output & "DATE:" & (date sent of msg as string) & linefeed
            on error
                set output to output & "DATE:Unknown" & linefeed
            end try
            set output to output & "BODY_START" & linefeed
            try
                set output to output & (content of msg) & linefeed
            on error
                set output to output & "(unable to read body)" & linefeed
            end try
            set output to output & "BODY_END" & linefeed
            set output to output & "---END_MESSAGE---" & linefeed
        end repeat
    end tell
    return output
    """

    /// Write the generated reply into the current compose window.
    /// Mail-scripting-only path: set `content of outgoing message 1`.
    /// Returns "INSERTED" on success and "NO_OUTGOING" when the compose
    /// window isn't visible to the scripting API (recent macOS versions) —
    /// `MailBridge` then falls back to the Accessibility writer
    /// (`AccessibilityWriter`), mirroring the read path's fallback.
    static func insertReply(_ text: String) -> String {
        let escaped = appleScriptString(text)
        let lines = escaped.components(separatedBy: "\n")
        let asString = lines.joined(separator: "\" & return & \"")
        return """
        set insertedViaAPI to false
        tell application "Mail"
            try
                if (count of outgoing messages) > 0 then
                    set outMsg to outgoing message 1
                    set oldContent to ""
                    try
                        set oldContent to content of outMsg
                    end try
                    set content of outMsg to "\(asString)" & return & return & oldContent
                    set insertedViaAPI to true
                end if
            on error errMsg
                -- fall through
            end try
        end tell

        if insertedViaAPI then
            return "INSERTED"
        end if
        return "NO_OUTGOING"
        """
    }

    /// Messages received since local midnight in Mail's unified Inbox.
    /// The script never mutates Mail and caps both record count and body size
    /// before data crosses into the app.
    static func fetchTodayInboxMessages(limit: Int) -> String {
        let safeLimit = max(1, min(limit, 100))
        return inboxScript(candidateExpression: "every message of inbox whose date received is greater than or equal to startOfToday", limit: safeLimit)
    }

    /// Subject/sender search in Mail's unified Inbox. Body search is omitted
    /// deliberately because forcing Mail to load every message body can block
    /// the app for minutes on a large mailbox.
    static func searchInboxMessages(query: String, limit: Int) -> String {
        let safeLimit = max(1, min(limit, 100))
        let escaped = appleScriptString(query)
        return inboxScript(
            prelude: "set searchText to \"\(escaped)\"",
            candidateExpression: "every message of inbox whose ((subject contains searchText) or (sender contains searchText))",
            limit: safeLimit
        )
    }

    /// Creates a saved, invisible reply draft for one Inbox message. It never
    /// invokes Mail's `send` command.
    static func createReplyDraft(messageID: Int, body: String) -> String {
        let escaped = appleScriptString(body)
        let lines = escaped.components(separatedBy: "\n")
        let asString = lines.joined(separator: "\" & return & \"")
        return """
        tell application "Mail"
            try
                set matches to every message of inbox whose id is \(messageID)
                if (count of matches) is 0 then return "ERROR:MESSAGE_NOT_FOUND"
                set sourceMessage to item 1 of matches
                set draftMessage to reply sourceMessage opening window false
                set originalContent to ""
                try
                    set originalContent to content of draftMessage
                end try
                set content of draftMessage to "\(asString)" & return & return & originalContent
                save draftMessage
                return "DRAFT_CREATED"
            on error errMsg
                return "ERROR:" & errMsg
            end try
        end tell
        """
    }

    static let fetchMessageViewerFrame = """
    tell application "Mail"
        if (count of message viewers) is 0 then return ""
        try
            set viewerBounds to bounds of window of message viewer 1
            return (item 1 of viewerBounds as text) & "," & (item 2 of viewerBounds as text) & "," & (item 3 of viewerBounds as text) & "," & (item 4 of viewerBounds as text)
        on error
            return ""
        end try
    end tell
    """

    private static func inboxScript(
        prelude: String = "set startOfToday to current date\nset time of startOfToday to 0",
        candidateExpression: String,
        limit: Int
    ) -> String {
        """
        on replaceText(findText, replacementText, sourceText)
            set oldDelimiters to AppleScript's text item delimiters
            set AppleScript's text item delimiters to findText
            set textItems to text items of sourceText
            set AppleScript's text item delimiters to replacementText
            set cleanValue to textItems as text
            set AppleScript's text item delimiters to oldDelimiters
            return cleanValue
        end replaceText

        on cleanText(theValue)
            try
                set valueText to theValue as text
            on error
                set valueText to ""
            end try
            set valueText to my replaceText(ASCII character 31, " ", valueText)
            set valueText to my replaceText(ASCII character 30, " ", valueText)
            return valueText
        end cleanText

        \(prelude)
        set fieldSeparator to ASCII character 31
        set recordSeparator to ASCII character 30
        set output to ""

        tell application "Mail"
            set candidates to \(candidateExpression)
            set candidateCount to count of candidates
            if candidateCount > \(limit) then set candidateCount to \(limit)

            repeat with itemIndex from 1 to candidateCount
                set msg to item itemIndex of candidates
                set bodyText to ""
                try
                    set bodyText to content of msg as text
                    if (length of bodyText) > 6000 then set bodyText to text 1 thru 6000 of bodyText
                end try

                set recordText to (id of msg as text) & fieldSeparator
                try
                    set recordText to recordText & my cleanText(message id of msg)
                end try
                set recordText to recordText & fieldSeparator & my cleanText(sender of msg)
                set recordText to recordText & fieldSeparator & my cleanText(subject of msg)
                set recordText to recordText & fieldSeparator & my cleanText(date received of msg)
                set recordText to recordText & fieldSeparator & my cleanText(bodyText)
                set recordText to recordText & fieldSeparator & (read status of msg as text)
                set recordText to recordText & fieldSeparator & (was replied to of msg as text)
                set output to output & recordText & recordSeparator
            end repeat
        end tell
        return output
        """
    }

    private static func appleScriptString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    static let checkMailRunning = """
    tell application "System Events"
        return (name of processes) contains "Mail"
    end tell
    """
}
