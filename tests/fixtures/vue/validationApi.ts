import axios from 'axios'

// A small Pinia-store-style API module exercising the cross-stack bridge.
export const validationApi = {
  check() {
    return axios.get('/api/validation/validate')
  },
  create(dto: ValidationDto) {
    return axios.post('/api/validation', dto)
  },
  remove(id: number) {
    return axios.delete(`/api/validation/${id}`)
  },
}
