<script>
import { mapGetters } from 'vuex';
import NextButton from 'dashboard/components-next/button/Button.vue';
import { useAlert, useToast } from 'dashboard/composables';
import QRCode from 'qrcode';

export default {
  components: {
    NextButton,
  },
  props: {
    inbox: {
      type: Object,
      required: true,
    },
  },
  data() {
    return {
      isLoading: false,
      qrCode: null,
      connectionStatus: 'pending',
      pollingInterval: null,
    };
  },
  computed: {
    ...mapGetters({
      currentInbox: 'inboxes/getCurrentInbox',
    }),
    channel() {
      return this.currentInbox?.channel;
    },
    isConnected() {
      return this.connectionStatus === 'connected';
    },
    isConnecting() {
      return this.connectionStatus === 'connecting';
    },
    isDisconnected() {
      return this.connectionStatus === 'disconnected' || this.connectionStatus === 'pending';
    },
  },
  mounted() {
    this.fetchConnectionStatus();
    this.startPolling();
  },
  beforeDestroy() {
    this.stopPolling();
  },
  methods: {
    async fetchConnectionStatus() {
      try {
        const response = await this.$store.dispatch('inboxes/getEvolutionStatus', {
          inboxId: this.inbox.id,
        });
        this.connectionStatus = response.status;
        if (response.qr_code) {
          this.qrCode = await this.buildQrImageSrc(response.qr_code);
        }
      } catch (error) {
        useAlert(this.$t('INBOX_MGMT.DETAILS.EVOLUTION.STATUS_ERROR'));
      }
    },
    async reconnect() {
      this.isLoading = true;
      try {
        await this.$store.dispatch('inboxes/reconnectEvolution', {
          inboxId: this.inbox.id,
        });
        useToast(this.$t('INBOX_MGMT.DETAILS.EVOLUTION.RECONNECT_SUCCESS'));
        this.fetchConnectionStatus();
      } catch (error) {
        useAlert(this.$t('INBOX_MGMT.DETAILS.EVOLUTION.RECONNECT_ERROR'));
      } finally {
        this.isLoading = false;
      }
    },
    async disconnect() {
      this.isLoading = true;
      try {
        await this.$store.dispatch('inboxes/disconnectEvolution', {
          inboxId: this.inbox.id,
        });
        useToast(this.$t('INBOX_MGMT.DETAILS.EVOLUTION.DISCONNECT_SUCCESS'));
        this.fetchConnectionStatus();
      } catch (error) {
        useAlert(this.$t('INBOX_MGMT.DETAILS.EVOLUTION.DISCONNECT_ERROR'));
      } finally {
        this.isLoading = false;
      }
    },
    startPolling() {
      this.pollingInterval = setInterval(() => {
        if (!this.isConnected) {
          this.fetchConnectionStatus();
        }
      }, 5000);
    },
    stopPolling() {
      if (this.pollingInterval) {
        clearInterval(this.pollingInterval);
      }
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
  <div class="flex flex-col gap-6 p-6">
    <div class="flex items-center justify-between">
      <div>
        <h3 class="text-lg font-semibold">
          {{ $t('INBOX_MGMT.DETAILS.EVOLUTION.TITLE') }}
        </h3>
        <p class="text-sm text-slate-500">
          {{ $t('INBOX_MGMT.DETAILS.EVOLUTION.DESC') }}
        </p>
      </div>
      <div class="flex items-center gap-2">
        <span
          :class="{
            'bg-green-100 text-green-800': isConnected,
            'bg-yellow-100 text-yellow-800': isConnecting,
            'bg-red-100 text-red-800': isDisconnected,
          }"
          class="px-3 py-1 rounded-full text-sm font-medium"
        >
          {{ $t(`INBOX_MGMT.DETAILS.EVOLUTION.STATUS.${connectionStatus.toUpperCase()}`) }}
        </span>
      </div>
    </div>

    <div v-if="qrCode && !isConnected" class="flex flex-col items-center gap-4 p-6 bg-slate-50 rounded-lg">
      <img :src="qrCode" alt="QR Code" class="w-64 h-64" />
      <p class="text-sm text-slate-600">
        {{ $t('INBOX_MGMT.DETAILS.EVOLUTION.SCAN_QR') }}
      </p>
    </div>

    <div v-if="isConnected" class="p-4 bg-green-50 rounded-lg">
      <p class="text-sm text-green-800">
        {{ $t('INBOX_MGMT.DETAILS.EVOLUTION.CONNECTED') }}
      </p>
    </div>

    <div class="flex gap-3">
      <NextButton
        v-if="!isConnected"
        :is-loading="isLoading"
        solid
        blue
        :label="$t('INBOX_MGMT.DETAILS.EVOLUTION.RECONNECT')"
        @click="reconnect"
      />
      <NextButton
        v-if="isConnected"
        :is-loading="isLoading"
        solid
        red
        :label="$t('INBOX_MGMT.DETAILS.EVOLUTION.DISCONNECT')"
        @click="disconnect"
      />
    </div>
  </div>
</template>
