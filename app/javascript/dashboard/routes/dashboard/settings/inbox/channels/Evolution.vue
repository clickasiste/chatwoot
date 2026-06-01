<script>
import { mapGetters } from 'vuex';
import { useVuelidate } from '@vuelidate/core';
import { required } from '@vuelidate/validators';
import { useAlert } from 'dashboard/composables';
import EvolutionAPI from 'dashboard/api/evolution';
import QRCode from 'qrcode';
import router from '../../../../index';
import PageHeader from '../../SettingsSubPageHeader.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

export default {
  components: {
    PageHeader,
    NextButton,
  },
  setup() {
    return { v$: useVuelidate() };
  },
  data() {
    return {
      channelName: '',
      instanceName: '',
      step: 'form',
      inboxId: null,
      channelId: null,
      qrCode: null,
      qrImageSrc: null,
      connectionStatus: 'pending',
      qrRefreshInterval: null,
      statusPollInterval: null,
    };
  },
  computed: {
    ...mapGetters({
      uiFlags: 'inboxes/getUIFlags',
    }),
    accountId() {
      return this.$route.params.accountId;
    },
  },
  validations: {
    channelName: { required },
    instanceName: { required },
  },
  beforeDestroy() {
    this.stopPolling();
  },
  methods: {
    async createChannel() {
      this.v$.$touch();
      if (this.v$.$invalid) {
        return;
      }

      try {
        const evolutionChannel = await this.$store.dispatch('inboxes/createChannel', {
          name: this.channelName?.trim(),
          channel: {
            type: 'evolution',
            instance_name: this.instanceName?.trim(),
          },
        });

        this.inboxId = evolutionChannel.id;
        this.channelId = evolutionChannel?.channel?.id || evolutionChannel?.channel_id || null;
        this.step = 'qr';
        await this.ensureChannelId();
        await this.fetchQrCode();
        await this.fetchConnectionStatus();
        this.startPolling();
      } catch (error) {
        useAlert(
          error.message ||
            this.$t('INBOX_MGMT.ADD.EVOLUTION.API.ERROR_MESSAGE')
        );
      }
    },
    async ensureChannelId() {
      if (!this.inboxId || this.channelId) return;

      const { data } = await EvolutionAPI.show(this.inboxId);
      this.channelId = data?.channel?.id || data?.channel_id || null;
    },
    startPolling() {
      this.stopPolling();

      this.qrRefreshInterval = setInterval(() => {
        if (this.connectionStatus !== 'connected') {
          this.fetchQrCode();
        }
      }, 30000);

      this.statusPollInterval = setInterval(() => {
        if (this.connectionStatus !== 'connected') {
          this.fetchConnectionStatus();
        }
      }, 5000);
    },
    stopPolling() {
      if (this.qrRefreshInterval) {
        clearInterval(this.qrRefreshInterval);
        this.qrRefreshInterval = null;
      }
      if (this.statusPollInterval) {
        clearInterval(this.statusPollInterval);
        this.statusPollInterval = null;
      }
    },
    async fetchQrCode() {
      if (!this.inboxId) return;
      try {
        await this.ensureChannelId();
        if (!this.channelId) return;

        const { data } = await EvolutionAPI.getQrCode(this.inboxId, this.channelId);
        this.qrCode = data?.qr_code || null;
        this.qrImageSrc = await this.buildQrImageSrc(this.qrCode);
        this.connectionStatus = data?.status || this.connectionStatus;
        if (this.connectionStatus === 'connected') {
          this.stopPolling();
        }
      } catch (_) {
      }
    },
    async fetchConnectionStatus() {
      if (!this.inboxId) return;
      try {
        await this.ensureChannelId();
        if (!this.channelId) return;

        const { data } = await EvolutionAPI.getConnectionStatus(this.inboxId, this.channelId);
        this.connectionStatus = data?.status || this.connectionStatus;
        if (this.connectionStatus === 'connected') {
          this.stopPolling();
        }
      } catch (_) {
      }
    },
    continueToAgents() {
      this.stopPolling();
      router.replace({
        name: 'settings_inboxes_add_agents',
        params: {
          page: 'new',
          inbox_id: this.inboxId,
        },
      });
    },
    async buildQrImageSrc(qrCode) {
      if (!qrCode) return null;

      if (qrCode.startsWith('data:image/')) return qrCode;

      if (/^[A-Za-z0-9+/=]+$/.test(qrCode) && qrCode.length > 200) {
        return `data:image/png;base64,${qrCode}`;
      }

      return QRCode.toDataURL(qrCode);
    },
  },
};
</script>

<template>
  <div class="h-full w-full p-6 col-span-6">
    <template v-if="step === 'form'">
      <PageHeader
        :header-title="$t('INBOX_MGMT.ADD.EVOLUTION.TITLE')"
        :header-content="$t('INBOX_MGMT.ADD.EVOLUTION.DESC')"
      />
      <form
        class="flex flex-wrap flex-col mx-0"
        @submit.prevent="createChannel()"
      >
        <div class="flex-shrink-0 flex-grow-0 mb-4">
          <label :class="{ error: v$.channelName.$error }">
            {{ $t('INBOX_MGMT.ADD.EVOLUTION.CHANNEL_NAME.LABEL') }}
            <input
              v-model="channelName"
              type="text"
              :placeholder="
                $t('INBOX_MGMT.ADD.EVOLUTION.CHANNEL_NAME.PLACEHOLDER')
              "
              @blur="v$.channelName.$touch"
            />
            <span v-if="v$.channelName.$error" class="message">
              {{ $t('INBOX_MGMT.ADD.EVOLUTION.CHANNEL_NAME.ERROR') }}
            </span>
          </label>
        </div>

        <div class="flex-shrink-0 flex-grow-0 mb-4">
          <label :class="{ error: v$.instanceName.$error }">
            {{ $t('INBOX_MGMT.ADD.EVOLUTION.INSTANCE_NAME.LABEL') }}
            <input
              v-model="instanceName"
              type="text"
              :placeholder="
                $t('INBOX_MGMT.ADD.EVOLUTION.INSTANCE_NAME.PLACEHOLDER')
              "
              @blur="v$.instanceName.$touch"
            />
            <span v-if="v$.instanceName.$error" class="message">
              {{ $t('INBOX_MGMT.ADD.EVOLUTION.INSTANCE_NAME.ERROR') }}
            </span>
          </label>
          <p class="help-text">
            {{ $t('INBOX_MGMT.ADD.EVOLUTION.INSTANCE_NAME.SUBTITLE') }}
          </p>
        </div>

        <div class="w-full mt-4">
          <NextButton
            :is-loading="uiFlags.isCreating"
            type="submit"
            solid
            blue
            :label="$t('INBOX_MGMT.ADD.EVOLUTION.SUBMIT_BUTTON')"
          />
        </div>
      </form>
    </template>

    <template v-else>
      <PageHeader
        header-title="Escanea el QR con WhatsApp"
        :header-content="`Estado: ${connectionStatus}`"
      />

      <div class="flex flex-col gap-6">
        <div v-if="qrImageSrc" class="flex flex-col items-center gap-4">
          <img :src="qrImageSrc" alt="QR Code" class="w-64 h-64" />
        </div>

        <div v-else class="text-sm text-slate-600">
          Cargando QR...
        </div>

        <div class="flex gap-3">
          <NextButton
            solid
            blue
            :label="'Continuar'"
            @click="continueToAgents"
          />
        </div>
      </div>
    </template>
  </div>
</template>
