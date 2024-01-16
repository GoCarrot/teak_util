# frozen_string_literal: true

require 'spec_helper'
require 'teak_util/storage/s3'

RSpec.describe TeakUtil::Storage::S3 do
  let(:client) { Aws::S3::Client.new(stub_responses: true) }
  let(:bucket) { 'test' }
  let(:prefix) { '' }
  let(:server_side_encryption) { 'aws:kms' }
  let(:kms_key_id) { nil }
  let(:acl) { 'private' }
  let(:key) { 'test/path' }
  let(:fully_qualified_key) { "#{prefix}#{key}" }
  let(:value) { 'test' }
  let(:opts) do
    {
      client: client,
      prefix: prefix,
      server_side_encryption: server_side_encryption,
      kms_key_id: kms_key_id,
      acl: acl
    }
  end

  subject(:storage) { described_class.new(bucket, opts) }

  shared_examples_for 'put' do
    it 'writes the object' do
      storage.put(key, value)
      expect(client).to have_received(:put_object).with(
        hash_including(bucket: bucket, key: fully_qualified_key, body: value)
      )
    end

    it 'returns the fully qualifed key' do
      expect(storage.put(key, value)).to eq fully_qualified_key
    end
  end

  shared_examples_for 'get' do
    let(:body) { 'response' }
    let(:client) do
      Aws::S3::Client.new(stub_responses: {
        get_object: { body: body }
      })
    end

    # We're calling through to the original to get our AWS stub response, and
    # we're using the rspec mock to ensure that we're retrieving the correct
    # object from the correct bucket
    before { allow(client).to receive(:get_object).and_call_original }

    it 'returns the value' do
      expect(storage.get(key)).to eq(body)
    end

    it 'retrieves the correct object' do
      storage.get(key)
      expect(client).to have_received(:get_object).with(
        hash_including(bucket: bucket, key: fully_qualified_key)
      )
    end
  end

  shared_examples_for 'del' do
    let(:client) do
      Aws::S3::Client.new(
        stub_responses: {
          delete_object: { }
        }
      )
    end

    before { allow(client).to receive(:delete_object).and_call_original }

    it 'deletes the correct object' do
      storage.del(key)
      expect(client).to have_received(:delete_object).with(
        hash_including(bucket: bucket, key: fully_qualified_key)
      )
    end
  end

  describe '#del' do
    include_examples 'del'

    context 'with a key prefix' do
      let(:prefix) { 'some/hierarchy/'}

      include_examples 'del'
    end
  end

  describe '#put' do
    before { allow(client).to receive(:put_object).and_call_original }

    include_examples 'put'

    context 'with a key prefix' do
      let(:prefix) { 'some/hierarchy/' }

      include_examples 'put'
    end

    it 'passes along content_type and content_disposition' do
      opts = { content_type: 'text/plain', content_disposition: 'attachment; fname="test.txt"' }
      storage.put(key, value, opts)
      expect(client).to have_received(:put_object).with(
        hash_including({bucket: bucket, key: fully_qualified_key, body: value}.merge(opts))
      )
    end
  end

  describe '#get' do
    include_examples 'get'

    context 'with a key prefix' do
      let(:prefix) { 'some/hierarchy/' }

      include_examples 'get'
    end

    context 'when the key does not exist' do
      let(:client) do
        Aws::S3::Client.new(stub_responses: {
          get_object: 'NoSuchKey'
        })
      end

      it 'returns nil' do
        expect(storage.get(key)).to be nil
      end
    end
  end
end
