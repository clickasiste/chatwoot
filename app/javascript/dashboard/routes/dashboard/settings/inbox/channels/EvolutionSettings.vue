<script>
import { mapGetters } from 'vuex';
import { useRouter } from 'vue-router';
import NextButton from 'dashboard/components-next/button/Button.vue';
import { useAlert } from 'dashboard/composables';
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
  setup() {
    const router = useRouter();
    return { router };
  },
  data() {
    return {
      isLoading: false,
      isDeleting: false,
      qrCode: null,
      connectionStatus: 'pending',
      pollingInterval: null,
      showDeleteConfirm: false,
    };
  },
  computed: {
    ...mapGetters({
      currentInbox: 'inboxes/getCurrentInbox',
    }),
    channel() {
      return this.currentInbox?.channel || this.inbox?.channel;
    },
    channelId() {
      return this.channel?.id;
    },
    phoneNumber() {
      return this.channel?.phone_number || this.inbox?.phone_number;
    },
    instanceName() {
      return this.channel?.instance_name;
    },
    isConnected() {
      return this.connectionStatus === 'connected';
    },
    isConnecting() {
      return this.connectionStatus === 'connecting';
    },
    isError() {
      return this.connectionStatus === 'error';
    },
    isDisconnected() {
      return this.connectionStatus === 'disconnected' || this.connectionStatus === 'pending';
    },
    statusLabel() {
      const map = {
        connected: 'Conectado',
        connecting: 'Conectando',
        disconnected: 'Desconectado',
        pending: 'Pendiente',
        error: 'Error',
      };
      return map[this.connectionStatus] || this.connectionStatus;
    },
  },
  mounted() {
    this.fetchConnectionStatus();
    this.startPolling();
  },
  unmounted() {
    this.stopPolling();
  },
  beforeDestroy() {
    this.stopPolling();
  },
  methods: {
    async fetchConnectionStatus() {
      if (!this.channelId) return;
      try {
        const response = await this.$store.dispatch('inboxes/getEvolutionStatus', {
          inboxId: this.inbox.id,
          channelId: this.channelId,
        });
        this.connectionStatus = response.status;
        if (response.qr_code) {
          this.qrCode = await this.buildQrImageSrc(response.qr_code);
        } else if (response.status === 'connected') {
          this.qrCode = null;
        }
      } catch (error) {
      }
    },
    async reconnect() {
      if (!this.channelId) return;
      this.isLoading = true;
      try {
        await this.$store.dispatch('inboxes/reconnectEvolution', {
          inboxId: this.inbox.id,
          channelId: this.channelId,
        });
        useAlert('Reconexión iniciada. Escanea el nuevo QR.');
        this.fetchConnectionStatus();
      } catch (error) {
        useAlert('Error al reconectar');
      } finally {
        this.isLoading = false;
      }
    },
    async disconnect() {
      if (!this.channelId) return;
      this.isLoading = true;
      try {
        await this.$store.dispatch('inboxes/disconnectEvolution', {
          inboxId: this.inbox.id,
          channelId: this.channelId,
        });
        useAlert('Desconectado');
        this.fetchConnectionStatus();
      } catch (error) {
        useAlert('Error al desconectar');
      } finally {
        this.isLoading = false;
      }
    },
    confirmDelete() {
      this.showDeleteConfirm = true;
    },
    cancelDelete() {
      this.showDeleteConfirm = false;
    },
    async deleteInbox() {
      if (!this.channelId) return;
      this.isDeleting = true;
      try {
        await this.$store.dispatch('inboxes/deleteEvolution', {
          inboxId: this.inbox.id,
          channelId: this.channelId,
        });
        useAlert('Inbox eliminado');
        this.stopPolling();
        if (this.router) {
          this.router.push({ name: 'settings_inbox_list' });
        } else {
          window.location.href =
            '/app/accounts/' + this.inbox.account_id + '/settings/inboxes/list';
        }
      } catch (error) {
        useAlert('Error al borrar el inbox');
        this.isDeleting = false;
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
        this.pollingInterval = null;
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
        <h3 class="text-lg font-semibold">WhatsApp (Evolution)</h3>
        <p class="text-sm text-slate-500">
          Gestiona la conexión de WhatsApp para este inbox
        </p>
      </div>
      <span
        :class="{
          'bg-green-100 text-green-800': isConnected,
          'bg-yellow-100 text-yellow-800': isConnecting,
          'bg-red-100 text-red-800': isDisconnected,
          'bg-red-200 text-red-900': isError,
        }"
        class="px-3 py-1 rounded-full text-sm font-medium"
      >
        {{ statusLabel }}
      </span>
    </div>

    <div
      v-if="phoneNumber || instanceName"
      class="grid grid-cols-1 md:grid-cols-2 gap-4 p-4 bg-slate-50 rounded-lg"
    >
      <div v-if="phoneNumber">
        <p class="text-xs text-slate-500 uppercase">Número conectado</p>
        <p class="text-sm font-mono mt-1">+{{ phoneNumber }}</p>
      </div>
      <div v-if="instanceName">
        <p class="text-xs text-slate-500 uppercase">Instance (técnico)</p>
        <p class="text-sm font-mono mt-1">{{ instanceName }}</p>
      </div>
    </div>

    <div
      v-if="qrCode && !isConnected"
      class="flex flex-col items-center gap-4 p-6 bg-slate-50 rounded-lg"
    >
      <img :src="qrCode" alt="QR Code" class="w-64 h-64" />
      <p class="text-sm text-slate-600">
        Escanea este código QR con WhatsApp en tu teléfono
      </p>
    </div>

    <div v-if="isConnected" class="p-4 bg-green-50 rounded-lg">
      <p class="text-sm text-green-800">✓ WhatsApp conectado y funcionando</p>
    </div>

    <div class="flex gap-3 flex-wrap">
      <NextButton
        v-if="!isConnected"
        :is-loading="isLoading"
        solid
        blue
        label="Reconectar"
        @click="reconnect"
      />
      <NextButton
        v-if="isConnected"
        :is-loading="isLoading"
        solid
        red
        label="Desconectar"
        @click="disconnect"
      />
      <NextButton
        :is-loading="isDeleting"
        outline
        red
        label="Borrar inbox"
        @click="confirmDelete"
      />
    </div>

    <div
      v-if="showDeleteConfirm"
      class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50"
      @click.self="cancelDelete"
    >
      <div class="bg-white rounded-lg p-6 max-w-md w-full mx-4">
        <h3 class="text-lg font-semibold mb-2">¿Borrar inbox?</h3>
        <p class="text-sm text-slate-600 mb-4">
          Esta acción es <strong>irreversible</strong>. Se eliminará el inbox
          de Chatwoot y la instancia de WhatsApp en Evolution. Todas las
          conversaciones quedarán archivadas pero el número ya no podrá enviar
          ni recibir mensajes.
        </p>
        <div class="flex gap-3 justify-end">
          <NextButton outline slate label="Cancelar" @click="cancelDelete" />
          <NextButton
            :is-loading="isDeleting"
            solid
            red
            label="Sí, borrar"
            @click="deleteInbox"
          />
        </div>
      </div>
    </div>
  </div>
</template>
