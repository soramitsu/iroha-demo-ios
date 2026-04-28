import UIKit
import IrohaSwift

final class TransactionCell: UITableViewCell {
    private let container = UIView()
    private let iconView = UIImageView()
    private let amountLabel = UILabel()
    private let counterpartyLabel = UILabel()
    private let statusContainer = UIView()
    private let statusLabel = UILabel()
    private let dateLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear

        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = .clear
        container.applyGlassCardStyle(cornerRadius: 22)
        contentView.addSubview(container)
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            container.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            container.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            container.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)
        ])

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = UIColor.glassPrimaryText
        container.addSubview(iconView)

        amountLabel.translatesAutoresizingMaskIntoConstraints = false
        amountLabel.font = UIFont.sora(.semiBold, size: 18)
        amountLabel.numberOfLines = 2
        amountLabel.textColor = UIColor.glassPrimaryText
        container.addSubview(amountLabel)

        counterpartyLabel.translatesAutoresizingMaskIntoConstraints = false
        counterpartyLabel.font = UIFont.sora(.medium, size: 14)
        counterpartyLabel.textColor = UIColor.glassSecondaryText
        counterpartyLabel.numberOfLines = 2
        container.addSubview(counterpartyLabel)

        statusContainer.translatesAutoresizingMaskIntoConstraints = false
        statusContainer.backgroundColor = UIColor.glassFieldBackground
        statusContainer.layer.cornerRadius = 12
        statusContainer.layer.masksToBounds = true
        container.addSubview(statusContainer)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = UIFont.sora(.semiBold, size: 12)
        statusLabel.textAlignment = .center
        statusLabel.textColor = UIColor.glassSecondaryText
        statusLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        statusContainer.addSubview(statusLabel)

        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        dateLabel.font = UIFont.sora(.regular, size: 12)
        dateLabel.textColor = UIColor.glassSecondaryText
        dateLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        container.addSubview(dateLabel)

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 36),
            iconView.heightAnchor.constraint(equalTo: iconView.widthAnchor),
            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            iconView.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),

            amountLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            amountLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            amountLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),

            counterpartyLabel.leadingAnchor.constraint(equalTo: amountLabel.leadingAnchor),
            counterpartyLabel.trailingAnchor.constraint(equalTo: amountLabel.trailingAnchor),
            counterpartyLabel.topAnchor.constraint(equalTo: amountLabel.bottomAnchor, constant: 6),

            statusContainer.leadingAnchor.constraint(equalTo: amountLabel.leadingAnchor),
            statusContainer.topAnchor.constraint(equalTo: counterpartyLabel.bottomAnchor, constant: 10),
            statusContainer.trailingAnchor.constraint(lessThanOrEqualTo: amountLabel.trailingAnchor),

            statusLabel.leadingAnchor.constraint(equalTo: statusContainer.leadingAnchor, constant: 10),
            statusLabel.trailingAnchor.constraint(equalTo: statusContainer.trailingAnchor, constant: -10),
            statusLabel.topAnchor.constraint(equalTo: statusContainer.topAnchor, constant: 6),
            statusLabel.bottomAnchor.constraint(equalTo: statusContainer.bottomAnchor, constant: -6),

            dateLabel.trailingAnchor.constraint(equalTo: amountLabel.trailingAnchor),
            dateLabel.centerYAnchor.constraint(equalTo: statusContainer.centerYAnchor),
            dateLabel.leadingAnchor.constraint(greaterThanOrEqualTo: statusContainer.trailingAnchor, constant: 12),

            container.bottomAnchor.constraint(greaterThanOrEqualTo: statusContainer.bottomAnchor, constant: 12),
            container.bottomAnchor.constraint(greaterThanOrEqualTo: iconView.bottomAnchor, constant: 12)
        ])

        contentView.applySoraFontsRecursively()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with item: ToriiTxItem, currentAccountId: String?, unit: String) {
        let isSender = item.authority?.caseInsensitiveCompare(currentAccountId ?? "") == .orderedSame
        iconView.image = UIImage(named: isSender ? "icon_send-2" : "icon_receive-2")?.withRenderingMode(.alwaysTemplate)
        iconView.tintColor = isSender ? UIColor.iroha : UIColor.irohaGreen
        let counterparty = item.authority ?? "Unknown"
        counterpartyLabel.text = isSender ? "To \(counterparty)" : "From \(counterparty)"
        let hashPrefix = String(item.entrypoint_hash.prefix(10)).uppercased()
        let direction = isSender ? "Sent" : "Received"
        amountLabel.text = "\(direction) • #\(hashPrefix)"
        let succeeded = item.result_ok
        statusLabel.text = succeeded ? "Succeeded" : "Failed"
        statusLabel.textColor = succeeded ? UIColor.irohaGreen : UIColor.iroha
        statusContainer.backgroundColor = (succeeded ? UIColor.irohaGreen : UIColor.iroha).withAlphaComponent(0.12)

        if let timestamp = item.timestamp_ms {
            let date = Date(timeIntervalSince1970: Double(timestamp) / 1000.0)
            if let relative = Self.relativeFormatter.string(from: date, to: Date()) {
                dateLabel.text = relative
            } else {
                dateLabel.text = Self.absoluteFormatter.string(from: date)
            }
        } else {
            dateLabel.text = ""
        }
    }

    private static let relativeFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.minute, .hour, .day]
        return formatter
    }()

    private static let absoluteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}
