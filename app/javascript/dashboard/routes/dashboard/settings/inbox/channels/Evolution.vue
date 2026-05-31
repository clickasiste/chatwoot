<script>
import { mapGetters } from 'vuex';
import { useVuelidate } from '@vuelidate/core';
import { required } from '@vuelidate/validators';
import { useAlert } from 'dashboard/composables';
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
    };
  },
  computed: {
    ...mapGetters({
      uiFlags: 'inboxes/getUIFlags',
    }),
  },
  validations: {
    channelName: { required },
    instanceName: { required },
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

        router.replace({
          name: 'settings_inboxes_add_agents',
          params: {
            page: 'new',
            inbox_id: evolutionChannel.id,
          },
        });
      } catch (error) {
        useAlert(
          error.message ||
            this.$t('INBOX_MGMT.ADD.EVOLUTION.API.ERROR_MESSAGE')
        );
      }
    },
  },
};
</script>

<template>
  <div class="h-full w-full p-6 col-span-6">
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
  </div>
</template>
