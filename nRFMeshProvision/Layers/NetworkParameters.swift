/*
* Copyright (c) 2023, Nordic Semiconductor
* All rights reserved.
*
* Redistribution and use in source and binary forms, with or without modification,
* are permitted provided that the following conditions are met:
*
* 1. Redistributions of source code must retain the above copyright notice, this
*    list of conditions and the following disclaimer.
*
* 2. Redistributions in binary form must reproduce the above copyright notice, this
*    list of conditions and the following disclaimer in the documentation and/or
*    other materials provided with the distribution.
*
* 3. Neither the name of the copyright holder nor the names of its contributors may
*    be used to endorse or promote products derived from this software without
*    specific prior written permission.
*
* THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
* ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
* WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
* IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
* INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
* NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
* PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
* WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
* ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
* POSSIBILITY OF SUCH DAMAGE.
*/

import Foundation

/// A set of network parameters that can be applied to the ``MeshNetworkManager``.
///
/// Network parameters configure the transsmition and retranssmition intervals,
/// acknowledge message timeout, the default Time To Live (TTL) and other.
///
/// Use ``NetworkParameters/default`` or ``NetworkParameters/custom(_:)`` to create
/// an instance of this structure.
///
/// - since: 4.0.0
public struct NetworkParameters {
    /// A builder type for ``NetworkParameters``.
    ///
    /// Parameters can be set one-by-one, or using a builder:
    /// ```swift
    /// meshNetworkManager.networkParameters = .custom { builder in
    ///     // Setting default Time To Live.
    ///     builder.defaultTtl = ...
    ///     // Setting a timeout to discard a partially received segmented message
    ///     // if no new segments were received.
    ///     builder.discardTimeout = ...
    ///     // Adjusting the rate of sending Segment Acknowledgment messages.
    ///     builder.setAcknowledgmentTimerInterval(..., andMinimumDelayIncrement: ...)
    ///     // Setting up Segment Acknowledgment retransmission.
    ///     builder.retranssmitSegmentAcknowledgmentMessages(..., timesWhenNumberOfSegmentsIsGreaterThan: ...)
    ///     builder.transmissionTimerInterval = ...
    ///     builder.retransmissionLimit = ...
    ///     builder.acknowledgmentMessageTimeout = ...
    ///     builder.acknowledgmentMessageInterval = ...
    ///     // If you know what you're doing, customize the advanced parameters.
    ///     builder.allowIvIndexRecoveryOver42 = ...
    ///     builder.ivUpdateTestMode = ...
    /// }
    /// ```
    ///
    /// If not modified, ``NetworkParameters/default`` values are used.
    public typealias Builder = (inout NetworkParameters) -> ()
    
    // MARK: - TTL states
    private var _defaultTtl: UInt8 = 5
    
    // MARK: - SAR Receiver states
    private var _sarDiscardTimeout: UInt8 = 0b0001              // (n+1)*5 sec = 10 seconds
    private var _sarAcknowledgmentDelayIncrement: UInt8 = 0b001 // n+1.5 = 2.5
    private var _sarReceiverSegmentIntervalStep: UInt8 = 0b0101 // (n+1)*10 ms = 60 ms
    private var _sarSegmentsThreshold: UInt8 = 0b00011          // 3
    private var _sarAcknowledgmentRetransmissionsCount: UInt8 = 0b00 // 0
    
    private var _transmissionTimerInterval: TimeInterval = 0.200
    private var _retransmissionLimit: Int = 5
    private var _acknowledgmentMessageTimeout: TimeInterval = 30.0
    private var _acknowledgmentMessageInterval: TimeInterval = 2.0
    
    // MARK: - TTL Configuration
    
    /// The Default TTL will be used for sending messages, if the value has
    /// not been set in the Provisioner's Node.
    ///
    /// By default it is set to 5, which is a reasonable value. The TTL shall be in range 2...127.
    ///
    /// In Bluetooth Mesh each message is sent with a given TTL value. When a relay
    /// Node receives such message it decrements the TTL value by 1, re-encrypts it
    /// using the same Network Key and retransmits further. If the received TTL value is
    /// 1 or 0 the message is no longer retransmitted.
    public var defaultTtl: UInt8 {
        get { return _defaultTtl }
        set { _defaultTtl = max(2, min(newValue, 127)) }
    }
    
    // MARK: - SAR Receiver state implementation
    
    /// The timeout after which an incomplete segmented message will be
    /// abandoned. The timer is restarted each time a segment of this
    /// message is received.
    ///
    /// The incomplete timeout should be set to at least 10 seconds.
    ///
    /// Mesh Protocol 1.1 replaced the Incomplete Message Timeout with
    /// a SAR Discard Timeout (``discardTimeout``).
    @available(*, deprecated, renamed: "discardTimeout")
    public var incompleteMessageTimeout: TimeInterval {
        get { return discardTimeout }
        set { discardTimeout = newValue }
    }
    
    /// The Discard Timeout is the time that the Lower Transport layer waits
    /// after receiving a new segment of a segmented message before
    /// discarding that segmented message.
    ///
    /// Valid range for this timeout is from 5 seconds to 1 minute and 20 seconds
    /// (80 seconds) with 5 second step. The default value is 10 seconds.
    ///
    /// The Discard Timeout is reset every time a new segment of a message
    /// is received.
    ///
    /// The value of this timeout is controlled by ``sarDiscardTimeout``
    /// state and is calculated the following way:
    /// ```
    /// (SAR Discard Timeout + 1) * 5 ms
    /// ```
    public var discardTimeout: TimeInterval {
        get { return TimeInterval(_sarDiscardTimeout + 1) * 5.0 }
        set { _sarDiscardTimeout = UInt8(min(5.0, newValue) / 5.0) - 1 }
    }
    
    /// The **SAR Discard Timeout state** is a 4-bit value that controls the time that the
    /// Lower Transport layer waits after receiving unique segments of a segmented
    /// message before discarding that segmented message.
    ///
    /// The default value of the **SAR Discard Timeout state** is `0b0001` (10 seconds).
    ///
    /// The Discard Timeout initial value is set using the following formula:
    /// ```
    /// (SAR Discard Timeout + 1) * 5 ms
    /// ```
    ///
    /// - seeAlso:``discardTimeout``
    public var sarDiscardTimeout: UInt8 {
        get { return _sarDiscardTimeout }
        set { _sarDiscardTimeout = min(newValue, 0b1111) } // Valid range: 0-15
    }
    
    /// This property used to control the time after which the lower transport
    /// layer sends a/ Segment Acknowledgment message after receiving a
    /// segment of a multi-segment message where the destination is the
    /// Unicast Address of one of the Provisioner's Elements
    ///
    /// In Bluetooth Mesh Profile 1.0.1 the inteval was dependent on Time To Live (TTL)
    /// and this property was used to adjust the constant part of the interval
    /// using the given formula:
    /// ```
    /// acknowledgment timer interval + (50 ms * TTL)
    /// ```
    /// The TTL dependent part was added automatically.
    ///
    /// - warning: In Bluetooth Mesh Protocol 1.1 this property was replace by
    ///            ``sarAcknowledgmentDelayIncrement`` and
    ///            ``sarReceiverSegmentIntervalStep`` which control
    ///            the interval using `segN` of a segmented message instead of `TTL`.
    ///            Setting this property does nothing.
    @available(*, deprecated, renamed: "setAcknowledgmentTimerInterval(_:andMinimumDelayIncrement:)")
    public var acknowledgmentTimerInterval: TimeInterval {
        get { return acknowledgmentTimerInterval(forLastSegmentNumber: 2) }
        set {
            // It is not possible to translate the old interval, which
            // depended on TTL value, to the new one, which is using number
            // of segments in a message.
        }
    }
    
    /// Sets the parameters for calculating the initial value fo SAR Acknowledgement timer.
    ///
    /// The initial value of SAR Acknowledgment timer is calculated with the following formula:
    /// ```
    /// min(SegN + 0.5, acknowledgment delay increment) * segment reception interval (ms)
    /// ```
    /// `SegN` field in a segmented message is the index of the last segment in a message,
    /// equal to the number of segments minus 1, therefore the formula can be also written as:
    /// ```
    /// min(number of segments - 0.5, acknowledgment delay increment) * segment reception interval (ms)
    /// ```
    ///
    /// - parameters:
    ///   - segmentReceptionInterval: The interval multipled by the number of segments in a
    ///                               message minus 0.5.
    ///                               Available values are in range 10 ms - 160 ms with 10 ms step.
    ///   - acknowledgmentDelayIncrement: The minimum delay increment. The value must be from
    ///                                   1.5 + n up to 8.5, that is 1.5, 2.5, 3.5, ... until 8.5.
    ///                                   Other values will be rounded down.
    public mutating func setAcknowledgmentTimerInterval(_ segmentReceptionInterval: TimeInterval,
                                                        andMinimumDelayIncrement acknowledgmentDelayIncrement: Double) {
        // Valid range: 10-160 ms
        _sarReceiverSegmentIntervalStep = UInt8((max(0.01, min(0.16, segmentReceptionInterval)) * 100) - 1)
        // Valid range: 1.5-8.5 segment transmission interval steps
        _sarAcknowledgmentDelayIncrement = UInt8(max(0, max(1.5, min(8.5, acknowledgmentDelayIncrement)) - 1.5))
    }
    
    /// The **SAR Acknowledgment Delay Increment state** is a 3-bit value that controls
    /// the interval between the reception of a new segment of a segmented message
    /// for a destination that is a Unicast Address and the transmission of the
    /// Segment Acknowledgment for that message.
    ///
    /// The default value of the **SAR Acknowledgment Delay Increment state** is `0b001`
    /// (2.5 segment transmission interval steps).
    ///
    /// - seeAlso:``sarReceiverSegmentIntervalStep``
    public var sarAcknowledgmentDelayIncrement: UInt8 {
        get { return _sarAcknowledgmentDelayIncrement }
        set { _sarAcknowledgmentDelayIncrement = min(newValue, 0b111) } // Valid range: 0-7
    }
    
    /// The **SAR Receiver Segment Interval Step state** is a 4-bit value that indicates
    /// the interval between received segments of a segmented message.
    /// This is used to control rate of transmission of Segment Acknowledgment messages.
    ///
    /// The default value of the **SAR Receiver Segment Interval Step state** is `0b0101`
    /// (60 milliseconds).
    ///
    /// - seeAlso:``sarAcknowledgmentDelayIncrement``
    public var sarReceiverSegmentIntervalStep: UInt8 {
        get { return _sarReceiverSegmentIntervalStep }
        set { _sarReceiverSegmentIntervalStep = min(newValue, 0b1111) } // Valid range: 0-15
    }
    
    /// A value indicated by the **SAR Acknowledgment Delay Increment state**.
    ///
    /// - seeAlso ``sarAcknowledgmentDelayIncrement``
    /// - seeAlso ``setAcknowledgmentTimerInterval(_:andMinimumDelayIncrement:)``
    public var acknowledgmentDelayIncrement: Double {
        get { return Double(_sarAcknowledgmentDelayIncrement) + 1.5 }
        set { _sarAcknowledgmentDelayIncrement = UInt8(max(0, max(1.5, min(8.5, newValue)) - 1.5)) }
    }
    
    /// A value indicated by the **SAR Receiver Segment Interval Step state**.
    ///
    /// - seeAlso ``sarReceiverSegmentIntervalStep``
    /// - seeAlso ``setAcknowledgmentTimerInterval(_:andMinimumDelayIncrement:)``
    public var segmentReceptionInterval: TimeInterval {
        get { return Double(_sarReceiverSegmentIntervalStep + 1) * 0.01 }
        set { _sarReceiverSegmentIntervalStep = UInt8(min(0.16, max(newValue, 0.01)) * 100) - 1 }
    }
    
    /// The initial value of the SAR Acknowledgment timer for a given `segN`.
    ///
    /// The value depends on the number of segments in a segmented message.
    ///
    /// The initial value of the SAR Acknowledgment timer is calculated using the following
    /// formula:
    /// ```
    /// min(SegN + 0.5 , acknowledgment delay increment) * segment reception interval (ms)
    /// ```
    /// where
    /// ```
    /// acknowledgment delay increment = SAR Acknowledgment Delay Increment + 1.5
    ///
    /// segment reception interval = (SAR Receiver Segment Interval Step + 1) × 10 ms
    /// ```
    internal func acknowledgmentTimerInterval(forLastSegmentNumber segN: UInt8) -> TimeInterval {
        return min(Double(segN) + 0.5, acknowledgmentDelayIncrement) * segmentReceptionInterval
    }
    
    /// The initial value of the timer ensuring that no more than one Segment Acknowledgment message
    /// is sent for the same SeqAuth value in a period of:
    /// ```
    /// acknowledgment delay increment * segment reception interval (ms)
    /// ```
    internal var completeAcknowledgmentTimerInterval: TimeInterval {
        return acknowledgmentDelayIncrement * segmentReceptionInterval
    }
    
    /// Sets the parameters controlling retransmission of Segment Acknowledgment messages
    /// for incomplete messages.
    ///
    /// When a Receiver receives a segment of asegmented message composed of 2 ro more
    /// segments it starts the SAR Acknowledgment timer. The initial value of this timer
    /// is controller by ``setAcknowledgmentTimerInterval(_:andMinimumDelayIncrement:)``
    /// and depends on the number of segments. When this timer expires and no new segment
    /// was received a Segment Acknowledgment message is sent to the Transmitter indicating
    /// which segments were received until that point. When the number of segments of the message
    /// is greater than the `threshold` and the `count` parameter is greater than 0 the
    /// Segment Acknowledgment message is retransmitted `count` times.
    ///
    /// By default retransmissions of Segment Acknowledgment messages are disabled.
    ///
    /// - parameters:
    ///   - count: Number of retransmissions of Segment Acknowledgment.
    ///            Valid values are 0-3, where 0 disables retransmissions.
    ///   - threshold: The number of segments above which the retransmissions of
    ///                Segment Acknowledgment messages are enabled.
    /// - seeAlso: ``sarSegmentsThreshold``
    /// - seeAlso: ``sarAcknowledgmentRetransmissionsCount``
    public mutating func retranssmitSegmentAcknowledgmentMessages(
        _ count: UInt8,
        timesWhenNumberOfSegmentsIsGreaterThan threshold: UInt8) {
        sarSegmentsThreshold = threshold
        sarAcknowledgmentRetransmissionsCount = count
    }
    
    /// The **SAR Segments Threshold state** is a 5-bit value that represents
    /// the size of a segmented message in number of segments above which the
    /// retransmissions of Segment Acknowledgment messages are enabled.
    ///
    /// Example: When a message is composed of 4 segments retransmissions of
    /// Segment Acknowledgment messages is enabled if the **SAR Segments
    /// Threshold state** is set to 3 or less.
    ///
    /// - note: Retransmissions of Segment Acknowledgment messages is always
    ///         disabled for single-segment segmented messages as they are complete
    ///         after receiving just one segment. The value of 0 and 1 are then
    ///         equivalent, as the shortest message for which Ack retransmissions
    ///         are enabled is 2 segments.
    ///
    /// The default value for the **SAR Segments Threshold state** is `0b00011` (3 segments).
    ///
    /// - seeAlso: ``sarAcknowledgmentRetransmissionsCount``
    /// - seeAlso: ``retranssmitSegmentAcknowledgmentMessages(_:timesWhenNumberOfSegmentsIsGreaterThan:)``
    public var sarSegmentsThreshold: UInt8 {
        get { return _sarSegmentsThreshold }
        set { _sarSegmentsThreshold = min(newValue, 0b11111) } // Valid range: 0-31
    }
    
    /// The **SAR Acknowledgment Retransmissions Count** state is a 2-bit value
    /// that controls the number of retransmissions of Segment Acknowledgment messages
    /// sent by the lower transport layer.
    ///
    /// Retransmission of Segment Acknowledgment messages is only enabled for messages
    /// composed of more segments then the value of ``sarSegmentsThreshold``.
    ///
    /// The maximum number of transmissions of a Segment Acknowledgment message is
    /// ```
    /// SAR Acknowledgment Retransmissions Count + 1
    /// ```
    /// For example, `0b00` represents a limit of 1 transmission, and `0b11` represents a limit of 4 transmissions.
    ///
    /// The default value of the **SAR Acknowledgment Retransmissions Count state** is `0b00`
    /// (1 transmission, retransmissions disabled).
    ///
    /// - note: Retransmission of Segment Acknowledgent messages is controlled by
    ///         ``sarSegmentsThreshold``.
    ///
    /// - seeAlso: ``sarSegmentsThreshold``
    /// - seeAlso: ``retranssmitSegmentAcknowledgmentMessages(_:timesWhenNumberOfSegmentsIsGreaterThan:)``
    public var sarAcknowledgmentRetransmissionsCount: UInt8 {
        get { return _sarAcknowledgmentRetransmissionsCount }
        set { _sarAcknowledgmentRetransmissionsCount = min(newValue, 0b11) }
    }
    
    /// The time within which a Segment Acknowledgment message is
    /// expected to be received after a segment of a segmented message has
    /// been sent. When the timer is fired, the non-acknowledged segments
    /// are repeated, at most ``retransmissionLimit`` times.
    ///
    /// The transmission timer shall be set to a minimum of
    /// 200 + 50 * TTL milliseconds. The TTL dependent part is added
    /// automatically, and this value shall specify only the constant part.
    ///
    /// If the bearer is using GATT, it is recommended to set the transmission
    /// interval longer than the connection interval, so that the acknowledgment
    /// had a chance to be received.
    public var transmissionTimerInterval: TimeInterval {
        get { return _transmissionTimerInterval }
        set { _transmissionTimerInterval = max(0.200, newValue) }
    }
    
    func transmissionTimerInterval(forTtl ttl: UInt8) -> TimeInterval {
        return _transmissionTimerInterval + Double(ttl) * 0.050
    }
    
    /// Number of times a non-acknowledged segment of a segmented message
    /// will be retransmitted before the message will be cancelled.
    ///
    /// The limit may be decreased with increasing of ``transmissionTimerInterval``
    /// as the target Node has more time to reply with the Segment
    /// Acknowledgment message.
    public var retransmissionLimit: Int {
        get { return _retransmissionLimit }
        set { _retransmissionLimit = max(2, newValue) }
    }
    
    // MARK: - Acknowledged messages configuration implementation
    
    /// If the Element does not receive a response within a period of time known
    /// as the acknowledged message timeout, then the Element may consider the
    /// message has not been delivered, without sending any additional messages.
    ///
    /// The ``MeshNetworkDelegate/meshNetworkManager(_:failedToSendMessage:from:to:error:)-7iylf``
    /// callback will be called on timeout.
    ///
    /// The acknowledged message timeout should be set to a minimum of 30 seconds.
    public var acknowledgmentMessageTimeout: TimeInterval {
        get { return _acknowledgmentMessageTimeout }
        set { _acknowledgmentMessageTimeout = max(30.0, newValue) }
    }
    
    /// The base time after which the acknowledged message will be repeated.
    ///
    /// The repeat timer will be set using the following formula:
    /// ```
    /// acknowledgment message interval + 50 ms * TTL + 50 ms * number of segments
    /// ```
    /// The TTL and segment count dependent parts are added
    /// automatically, and this value shall specify only the constant part.
    public var acknowledgmentMessageInterval: TimeInterval {
        get { return _acknowledgmentMessageInterval }
        set { _acknowledgmentMessageInterval = max(2.0, newValue) }
    }
    
    internal func acknowledgmentMessageInterval(forTtl ttl: UInt8, andSegmentCount segmentCount: Int) -> TimeInterval {
        return _acknowledgmentMessageInterval + Double(ttl) * 0.050 + Double(segmentCount) * 0.050
    }
    
    // MARK: - Advanced configuration
    
    /// According to Bluetooth Mesh Profile 1.0.1, section 3.10.5, if the IV Index
    /// of the mesh network increased by more than 42 since the last connection
    /// (which can take at least 48 weeks), the Node should be re-provisioned.
    /// However, as this library can be used to provision other Nodes, it should not
    /// be blocked from sending messages to the network only because the phone wasn't
    /// connected to the network for that time. This flag can disable this check,
    /// effectively allowing such connection.
    ///
    /// The same can be achieved by clearing the app data (uninstalling and reinstalling
    /// the app) and importing the mesh network. With no "previous" IV Index, the
    /// library will accept any IV Index received in the Secure Network beacon upon
    /// connection to the GATT Proxy Node.
    public var allowIvIndexRecoveryOver42: Bool = false
    
    /// IV Update Test Mode enables efficient testing of the IV Update procedure.
    /// The IV Update test mode removes the 96-hour limit; all other behavior of the device
    /// are unchanged.
    ///
    /// - seeAlso: Bluetooth Mesh Profile 1.0.1, section 3.10.5.1.
    public var ivUpdateTestMode: Bool = false
    
    // MARK: - Initializers
    
    /// A builder for custom configuration.
    ///
    /// - parameter with: The configuration builder.
    /// - returns: The built network parameters object.
    public static func custom(_ builder: Builder) -> NetworkParameters {
        var provider = NetworkParameters()
        builder(&provider)
        return provider
    }
    
    /// A set of default network parameters.
    public static let `default` = NetworkParameters()
        
    private init() {
        // Private constructor.
    }
}

/// The network parameters provider.
public protocol NetworkParametersProvider: AnyObject {
    
    /// Network parameters.
    var networkParameters: NetworkParameters { get }
    
}
