/* global axios */
import ApiClient from './ApiClient';

class EvolutionAPI extends ApiClient {
  constructor() {
    super('inboxes', { accountScoped: true });
  }

  getQrCode(inboxId, channelId) {
    return axios.get(`${this.url}/${inboxId}/evolution/${channelId}/get_qr_code`);
  }

  getConnectionStatus(inboxId, channelId) {
    return axios.get(
      `${this.url}/${inboxId}/evolution/${channelId}/connection_status`
    );
  }
}

export default new EvolutionAPI();
