/* global axios */
import ApiClient from './ApiClient';

class EvolutionAPI extends ApiClient {
  constructor() {
    super('inboxes', { accountScoped: true });
  }

  getQrCode(inboxId, channelId) {
    return axios.get(
      `${this.url}/${inboxId}/evolution/${channelId}/get_qr_code`
    );
  }

  getConnectionStatus(inboxId, channelId) {
    return axios.get(
      `${this.url}/${inboxId}/evolution/${channelId}/connection_status`
    );
  }

  reconnect(inboxId, channelId) {
    return axios.post(
      `${this.url}/${inboxId}/evolution/${channelId}/reconnect`
    );
  }

  disconnect(inboxId, channelId) {
    return axios.post(
      `${this.url}/${inboxId}/evolution/${channelId}/disconnect`
    );
  }

  deleteInstance(inboxId, channelId) {
    return axios.delete(
      `${this.url}/${inboxId}/evolution/${channelId}/delete_instance`
    );
  }
}

export default new EvolutionAPI();
