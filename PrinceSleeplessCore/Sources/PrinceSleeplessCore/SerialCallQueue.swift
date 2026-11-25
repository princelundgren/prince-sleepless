/// Calls that run one at a time, first in, first out. Each ticket completes once: completing a
/// ticket that isn't the running one, such as one already completed, changes nothing.
public struct SerialCallQueue<Call: Sendable>: Sendable {
    /// One queued call. It has no public initializer on purpose: only `enqueue` makes tickets, so
    /// no caller can forge one and complete a call it wasn't handed.
    public struct Ticket: Sendable {
        public let call: Call
        fileprivate let number: Int
    }

    /// The call that runs now; `nil` while the queue is empty.
    public private(set) var running: Ticket?
    private var waiting: [Ticket] = []
    private var lastNumber = 0

    public init() {}

    /// Queues `call`. Returns its ticket when nothing was running, for the caller to start now;
    /// `nil` when it waits for the calls before it.
    public mutating func enqueue(_ call: Call) -> Ticket? {
        lastNumber += 1
        let ticket = Ticket(call: call, number: lastNumber)
        guard running == nil else {
            waiting.append(ticket)
            return nil
        }
        running = ticket
        return ticket
    }

    /// Completes `ticket` and makes the next waiting call `running`, for the caller to start.
    /// Returns `false`, changing nothing, when `ticket` isn't the running one.
    public mutating func complete(_ ticket: Ticket) -> Bool {
        guard running?.number == ticket.number else { return false }
        running = waiting.isEmpty ? nil : waiting.removeFirst()
        return true
    }
}
