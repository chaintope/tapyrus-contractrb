module Glueby
  # # Glueby::Wallet
  #
  # This module provides the way to deal about wallet that includes key management, address management, getting UTXOs.
  #
  # ## How to use
  #
  # First, you need to configure which wallet implementation is used in Glueby::Wallet. For now, below wallets are
  # supported.
  #
  # * [Tapyrus Core](https://github.com/chaintope/tapyrus-core)
  #
  # Here shows an example to use Tapyrus Core wallet.
  #
  # ```ruby
  # # Setup Tapyrus Core RPC connection
  # config = {schema: 'http', host: '127.0.0.1', port: 12381, user: 'user', password: 'pass'}
  # Glueby::Contract::RPC.configure(config)
  #
  # # Setup wallet adapter
  # Glueby::Wallet.wallet_adapter = Glueby::Wallet::TapyrusCoreWalletAdapter.new
  #
  # # Create wallet
  # wallet = Glueby::Wallet.create
  # wallet.balance # => 0
  # wallet.list_unspent
  # ```
  class Wallet
    autoload :AbstractWalletAdapter, 'glueby/wallet/abstract_wallet_adapter'
    autoload :TapyrusCoreWalletAdapter, 'glueby/wallet/tapyrus_core_wallet_adapter'
    autoload :Errors, 'glueby/wallet/errors'

    class << self
      attr_writer :wallet_adapter

      def create
        new(wallet_adapter.create_wallet)
      end

      def load(wallet_id)
        wallet_adapter.load_wallet(wallet_id)
        new(wallet_id)
      end

      def wallets
        wallet_adapter.wallets.map { |id| new(id) }
      end

      def wallet_adapter
        @wallet_adapter or
          raise Errors::ShouldInitializeWalletAdapter, 'You should initialize wallet adapter using `Glueby::Wallet.wallet_adapter = some wallet adapter instance`.'

        @wallet_adapter
      end
    end

    attr_reader :id

    def initialize(wallet_id)
      @id = wallet_id
    end

    def balance(only_finalized = true)
      wallet_adapter.balance(id, only_finalized)
    end

    def list_unspent(only_finalized = true)
      wallet_adapter.list_unspent(id, only_finalized)
    end

    def delete
      wallet_adapter.delete_wallet(id)
    end

    def sign_tx(tx)
      wallet_adapter.sign_tx(id, tx)
    end

    def receive_address
      wallet_adapter.receive_address(id)
    end

    def change_address
      wallet_adapter.change_address(id)
    end

    def create_pubkey
      wallet_adapter.pubkey(id)
    end

    private

    def wallet_adapter
      self.class.wallet_adapter
    end
  end
end