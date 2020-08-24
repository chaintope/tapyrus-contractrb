# frozen_string_literal: true

module Glueby
  module Contract
    module TokenTxBuilder
      using Glueby::Wallet::InternalWallet

      def receive_address(wallet:)
        wallet.receive_address
      end

      # Create new public key, and new transaction that sends TPC to it
      def create_funding_tx(wallet:, amount:, script: nil, fee_provider: FixedFeeProvider.new)
        tx = Tapyrus::Tx.new
        fee = fee_provider.fee(tx)

        utxos = wallet.list_unspent
        sum, outputs = collect_uncolored_outputs(utxos, fee + amount)
        fill_input(tx, outputs)

        receiver_script = script ? script : Tapyrus::Script.parse_from_addr(wallet.receive_address)
        tx.outputs << Tapyrus::TxOut.new(value: amount, script_pubkey: receiver_script)

        fill_change_tpc(tx, wallet, sum - fee - amount)
        wallet.sign_tx(tx)
      end

      def create_issue_tx_for_reissuable_token(funding_tx:, issuer:, amount:, fee_provider: FixedFeeProvider.new)
        tx = Tapyrus::Tx.new
        fee = fee_provider.fee(tx)

        out_point = Tapyrus::OutPoint.from_txid(funding_tx.txid, 0)
        tx.inputs << Tapyrus::TxIn.new(out_point: out_point)
        output = funding_tx.outputs.first

        receiver_script = Tapyrus::Script.parse_from_addr(issuer.receive_address)
        color_id = Tapyrus::Color::ColorIdentifier.reissuable(receiver_script)
        receiver_colored_script = receiver_script.add_color(color_id)
        tx.outputs << Tapyrus::TxOut.new(value: amount, script_pubkey: receiver_colored_script)

        fill_change_tpc(tx, issuer, output.value - fee)
        prev_txs = [{
          txid: funding_tx.txid,
          vout: 0,
          scriptPubKey: output.script_pubkey.to_hex,
          amount: output.value
        }]
        signed = issuer.sign_tx(tx, prev_txs)
        signed
      end

      def create_issue_tx_for_non_reissuable_token(issuer:, amount:, fee_provider: FixedFeeProvider.new)
        tx = Tapyrus::Tx.new
        fee = fee_provider.fee(tx)

        utxos = issuer.list_unspent
        sum, outputs = collect_uncolored_outputs(utxos, fee)
        fill_input(tx, outputs)

        out_point = tx.inputs.first.out_point
        color_id = Tapyrus::Color::ColorIdentifier.non_reissuable(out_point)

        receiver_script = Tapyrus::Script.parse_from_addr(issuer.receive_address)
        receiver_colored_script = receiver_script.add_color(color_id)
        tx.outputs << Tapyrus::TxOut.new(value: amount, script_pubkey: receiver_colored_script)

        fill_change_tpc(tx, issuer, sum - fee)
        issuer.sign_tx(tx)
      end

      def create_issue_tx_for_nft_token(issuer:, fee_provider: FixedFeeProvider.new)
        tx = Tapyrus::Tx.new
        fee = fee_provider.fee(tx)

        utxos = issuer.list_unspent
        sum, outputs = collect_uncolored_outputs(utxos, fee)
        fill_input(tx, outputs)

        out_point = tx.inputs.first.out_point
        color_id = Tapyrus::Color::ColorIdentifier.nft(out_point)

        receiver_script = Tapyrus::Script.parse_from_addr(issuer.receive_address)
        receiver_colored_script = receiver_script.add_color(color_id)
        tx.outputs << Tapyrus::TxOut.new(value: 1, script_pubkey: receiver_colored_script)

        fill_change_tpc(tx, issuer, sum - fee)
        issuer.sign_tx(tx)
      end

      def create_reissue_tx(funding_tx:, issuer:, amount:, color_id:, fee_provider: FixedFeeProvider.new)
        tx = Tapyrus::Tx.new
        fee = fee_provider.fee(tx)

        out_point = Tapyrus::OutPoint.from_txid(funding_tx.txid, 0)
        tx.inputs << Tapyrus::TxIn.new(out_point: out_point)
        output = funding_tx.outputs.first

        receiver_script = Tapyrus::Script.parse_from_addr(issuer.receive_address)
        receiver_colored_script = receiver_script.add_color(color_id)
        tx.outputs << Tapyrus::TxOut.new(value: amount, script_pubkey: receiver_colored_script)

        fill_change_tpc(tx, issuer, output.value - fee)
        prev_txs = [{
          txid: funding_tx.txid,
          vout: 0,
          scriptPubKey: output.script_pubkey.to_hex,
          amount: output.value
        }]
        issuer.sign_tx(tx, prev_txs)
      end

      def create_transfer_tx(color_id:, sender:, receiver:, amount:, fee_provider: FixedFeeProvider.new)
        tx = Tapyrus::Tx.new
        fee = fee_provider.fee(tx)

        utxos = sender.list_unspent
        sum_tpc, outputs = collect_uncolored_outputs(utxos, fee)
        fill_input(tx, outputs)

        sum_token, outputs = collect_colored_outputs(utxos, color_id, amount)
        fill_input(tx, outputs)

        receiver_script = Tapyrus::Script.parse_from_addr(receiver.receive_address)
        receiver_colored_script = receiver_script.add_color(color_id)
        tx.outputs << Tapyrus::TxOut.new(value: amount, script_pubkey: receiver_colored_script)

        fill_change_token(tx, sender, sum_token - amount, color_id)
        fill_change_tpc(tx, sender, sum_tpc - fee)
        sender.sign_tx(tx)
      end

      def create_burn_tx(color_id:, sender:, amount: 0, fee_provider: FixedFeeProvider.new)
        tx = Tapyrus::Tx.new
        fee = fee_provider.fee(tx)

        utxos = sender.list_unspent
        dust = 600 # in case that the wallet has output which has just fee amount.
        sum_tpc, outputs = collect_uncolored_outputs(utxos, fee + dust)
        fill_input(tx, outputs)

        sum_token, outputs = collect_colored_outputs(utxos, color_id, amount)
        fill_input(tx, outputs)

        fill_change_token(tx, sender, sum_token - amount, color_id) if amount.positive?

        fill_change_tpc(tx, sender, sum_tpc - fee)
        sender.sign_tx(tx)
      end

      def fill_input(tx, outputs)
        outputs.each do |output|
          out_point = Tapyrus::OutPoint.new(output[:txid].rhex, output[:vout])
          tx.inputs << Tapyrus::TxIn.new(out_point: out_point)
        end
      end

      def fill_change_tpc(tx, wallet, change)
        return unless change.positive?

        change_script = Tapyrus::Script.parse_from_addr(wallet.change_address)
        tx.outputs << Tapyrus::TxOut.new(value: change, script_pubkey: change_script)
      end

      def fill_change_token(tx, wallet, change, color_id)
        return unless change.positive?

        change_script = Tapyrus::Script.parse_from_addr(wallet.change_address)
        change_colored_script = change_script.add_color(color_id)
        tx.outputs << Tapyrus::TxOut.new(value: change, script_pubkey: change_colored_script)
      end

      def collect_uncolored_outputs(results, amount)
        results.inject([0, []]) do |sum, output|
          script = Tapyrus::Script.parse_from_payload(output[:script_pubkey].htb)
          next sum if script.cp2pkh? || script.cp2sh?

          new_sum = sum[0] + output[:amount]
          new_outputs = sum[1] << output
          return [new_sum, new_outputs] if new_sum >= amount

          [new_sum, new_outputs]
        end
        raise Glueby::Contract::Errors::InsufficientFunds
      end

      def collect_colored_outputs(results, color_id, amount = 0)
        results = results.inject([0, []]) do |sum, output|
          script = Tapyrus::Script.parse_from_payload(output[:script_pubkey].htb)
          next sum unless script.cp2pkh? || script.cp2sh?
          next sum unless Tapyrus::Color::ColorIdentifier.parse_from_payload(script.chunks[0].pushed_data) == color_id

          new_sum = sum[0] + output[:amount]
          new_outputs = sum[1] << output
          return [new_sum, new_outputs] if new_sum >= amount && amount.positive?

          [new_sum, new_outputs]
        end
        raise Glueby::Contract::Errors::InsufficientTokens if amount.positive?

        results
      end
    end
  end
end
