RSpec.shared_examples 'If the wallet is unloaded, it should raise WalletUnloaded error.' do
  let(:rpc_name) { :listunspent }
  it 'should raise WalletUnloaded error.' do
    expect(rpc).to receive(rpc_name)
                     .and_raise(RuntimeError.new('{"code"=>-18, "message"=>"Requested wallet does not exist or is not loaded"}'))
    expect { subject }
      .to raise_error(
        Glueby::Wallet::Errors::WalletUnloaded,
        "The wallet #{wallet_id} is unloaded. You should load before use it."
      )
  end
end

RSpec.describe 'Glueby::Wallet::TapyrusCoreWalletAdapter' do
  let(:adapter) { Glueby::Wallet::TapyrusCoreWalletAdapter.new }
  let(:rpc) { double('mock') }

  before do
    allow(Glueby::Contract::RPC).to receive(:client).and_return(rpc)
    allow(Glueby::Contract::RPC).to receive(:switch_wallet) { |&block| block.call(rpc) }
  end

  describe 'create_wallet' do
    subject { adapter.create_wallet }
    
    let(:response) do
      {
        'name' => 'wallet-0828d0ce8ff358cd0d7b19ac5c43c3bbc77c9e42c062174d2901db8caa3a361b',
        'warning'=> ''
      }
    end

    it 'should call createwallet RPC' do
      expect(rpc).to receive(:createwallet).and_return(response)
      subject
    end
  end

  describe 'wallets' do
    subject { adapter.wallets }

    let(:response) do
      [
        '',
        '1',
        'wallet-2077c01e386889faa675f434498a4fb469c11adcb40e808459a6913f96aea0e4',
        'wallet-c23366c9d24493db1bcd38955bd7347d5d7b248165e7da9f92c6d314cbc3ccd9'
      ]
    end

    it 'should returns array of wallet ids that is the tail of wallet names which starts with "wallet-" prefix.' do
      expect(rpc).to receive(:listwallets).and_return(response)
      expect(subject).to eq %w[2077c01e386889faa675f434498a4fb469c11adcb40e808459a6913f96aea0e4
                               c23366c9d24493db1bcd38955bd7347d5d7b248165e7da9f92c6d314cbc3ccd9]
    end
  end

  describe 'balance' do
    subject { adapter.balance(wallet_id) }
    let(:wallet_id) { SecureRandom.hex(32) }

    let(:response) { '0.00000100' }

    it 'should return balance as tapyrus unit' do
      expect(rpc).to receive(:getbalance).with('*', 1).and_return(response)
      expect(subject).to be_a Integer
      expect(subject).to eq 100
    end

    context 'only_finalized is false' do
      subject { adapter.balance(wallet_id, only_finalized) }
      let(:only_finalized) { false }
      it 'should call getbalance RPC and getunconfirmedbalance RPC' do
        expect(rpc).to receive(:getbalance).with('*', 1).and_return(response)
        expect(rpc).to receive(:getunconfirmedbalance).and_return('0.00000200')
        expect(subject).to eq 300
      end
    end

    it_behaves_like 'If the wallet is unloaded, it should raise WalletUnloaded error.' do
      let(:rpc_name) { :getbalance }
    end
  end

  describe 'list_unspent' do
    subject { adapter.list_unspent(wallet_id, only_finalized) }

    let(:wallet_id) { SecureRandom.hex(32) }
    let(:only_finalized) { nil }

    let(:response) do
      JSON.parse(<<-JSON)
        [
          {
            "txid": "5c3d79041ff4974282b8ab72517d2ef15d8b6273cb80a01077145afb3d5e7cc5",
            "vout": 0,
            "address": "mijMuQ8L4EeWZWs4rB5mc3ya2dEie4u2u8",
            "label": "",
            "scriptPubKey": "76a914234113b860822e68f9715d1957af28b8f5117ee288ac",
            "amount": "1.00000000",
            "confirmations": 0,
            "spendable": true,
            "solvable": true,
            "safe": false
          },
          {
            "txid": "1d49c8038943d37c2723c9c7a1c4ea5c3738a9bad5827ddc41e144ba6aef36db",
            "vout": 1,
            "address": "mijMuQ8L4EeWZWs4rB5mc3ya2dEie4u2u8",
            "label": "",
            "scriptPubKey": "76a914234113b860822e68f9715d1957af28b8f5117ee288ac",
            "amount": "1.00000000",
            "confirmations": 12,
            "spendable": true,
            "solvable": true,
            "safe": false
          }
        ]
      JSON
    end

    it 'should call listunspent RPC and parse the results.' do
      expect(rpc).to receive(:listunspent).and_return(response)
      expect(subject).to eq([
                              {
                                txid: "5c3d79041ff4974282b8ab72517d2ef15d8b6273cb80a01077145afb3d5e7cc5",
                                vout: 0,
                                amount: 100000000,
                                finalized: false
                              },
                              {
                                txid: "1d49c8038943d37c2723c9c7a1c4ea5c3738a9bad5827ddc41e144ba6aef36db",
                                vout: 1,
                                amount: 100000000,
                                finalized: true
                              }
                            ])
    end

    context 'only_finalized is false' do
      let(:only_finalized) { false }
      it 'should call listunspent RPC with min_conf = 0' do
        expect(rpc).to receive(:listunspent).with(0, 999_999).and_return(response)
        subject
      end
    end

    context 'only_finalized is true' do
      let(:only_finalized) { true }
      it 'should call getbalance RPC with min_conf = 1' do
        expect(rpc).to receive(:listunspent).with(1, 999_999).and_return(response)
        subject
      end
    end

    it_behaves_like 'If the wallet is unloaded, it should raise WalletUnloaded error.' do
      let(:rpc_name) { :listunspent }
    end
  end

  describe 'sign_tx' do
    subject { adapter.sign_tx(wallet_id, tx) }

    let(:wallet_id) { SecureRandom.hex(32) }
    let(:tx) { Tapyrus::Tx.parse_from_payload("01000000010c22d3f121927c8a241a93cfbb1d6afc451ec7d32e8d37d63eb78d69afc555050000000000ffffffff020000000000000000226a204bf5122f344554c53bde2ebb8cd2b7e3d1600ad631c385a5d7cce23c7785459af0b9f505000000001976a9141989373d44a421a92df00d0237ab85dadd1d229088ac00000000".htb) }

    let(:response) do
      {
        'hex' => '01000000010c22d3f121927c8a241a93cfbb1d6afc451ec7d32e8d37d63eb78d69afc555050000000000ffffffff020000000000000000226a204bf5122f344554c53bde2ebb8cd2b7e3d1600ad631c385a5d7cce23c7785459af0b9f505000000001976a914b0179f0d7d738a51cca26d54d50329cab60a8c1388ac00000000'
      }
    end

    it 'should call signrawtransactionwithwallet RPC' do
      expect(rpc).to receive(:signrawtransactionwithwallet).and_return(response)
      subject
    end

    it_behaves_like 'If the wallet is unloaded, it should raise WalletUnloaded error.' do
      let(:rpc_name) { :signrawtransactionwithwallet }
    end
  end

  describe 'receive_address' do
    subject { adapter.receive_address(wallet_id) }

    let(:wallet_id) { SecureRandom.hex(32) }
    let(:response) { 'mjRTJ97nY3zVuvspVQcCoKf3Q8zanVGF8g' }

    it 'should call getnewaddress RPC' do
      expect(rpc).to receive(:getnewaddress).with('', 'legacy').and_return(response)
      subject
    end

    it_behaves_like 'If the wallet is unloaded, it should raise WalletUnloaded error.' do
      let(:rpc_name) { :getnewaddress }
    end
  end

  describe 'change_address' do
    subject { adapter.change_address(wallet_id) }

    let(:wallet_id) { SecureRandom.hex(32) }
    let(:response) { 'mjRTJ97nY3zVuvspVQcCoKf3Q8zanVGF8g' }

    it 'should call getrawchangeaddress RPC' do
      expect(rpc).to receive(:getrawchangeaddress).with('legacy').and_return(response)
      subject
    end

    it_behaves_like 'If the wallet is unloaded, it should raise WalletUnloaded error.' do
      let(:rpc_name) { :getrawchangeaddress }
    end
  end

  describe 'pubkey' do
    subject { adapter.pubkey(wallet_id) }

    let(:wallet_id) { SecureRandom.hex(32) }
    let(:getnewaddress_response) { 'mueLMubHXrk6ZxLb1H2C45rT7rraFvkrXM' }
    let(:getaddressinfo_response) do
      JSON.parse(<<-JSON)
        {
          "address": "mueLMubHXrk6ZxLb1H2C45rT7rraFvkrXM",
          "scriptPubKey": "76a9149af717c481168e2b16416936277b36eb43eb2bc688ac",
          "ismine": true,
          "iswatchonly": false,
          "isscript": false,
          "iswitness": false,
          "pubkey": "03bfb1e7949dd62696cc9a8d94bf7de19e764ef0579e8bd3afa7d00642c4162e0e",
          "iscompressed": true,
          "label": "",
          "timestamp": 1594777657,
          "hdkeypath": "m/0'/0'/1'",
          "hdseedid": "a78c55210711b68c0a8fabc29d4277411d77943d",
          "hdmasterkeyid": "a78c55210711b68c0a8fabc29d4277411d77943d",
          "labels": [
            {
              "name": "",
              "purpose": "receive"
            }
          ]
        }
      JSON
    end

    it 'should call getnewaddress and getaddressinfo RPC and returns compressed pubkey.' do
      expect(rpc).to receive(:getnewaddress)
                       .with('', 'legacy')
                       .and_return(getnewaddress_response)
      expect(rpc).to receive(:getaddressinfo)
                       .with(getnewaddress_response)
                       .and_return(getaddressinfo_response)
      expect(subject.pubkey).to eq '03bfb1e7949dd62696cc9a8d94bf7de19e764ef0579e8bd3afa7d00642c4162e0e'
    end

    it_behaves_like 'If the wallet is unloaded, it should raise WalletUnloaded error.' do
      let(:rpc_name) { :getnewaddress }
    end
  end
end