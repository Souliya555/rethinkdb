#ifndef CLUSTERING_ADMINISTRATION_HTTP_LAST_SEEN_APP_HPP_
#define CLUSTERING_ADMINISTRATION_HTTP_LAST_SEEN_APP_HPP_

#include "clustering/administration/last_seen_tracker.hpp"
#include "http/http.hpp"
#include "http/json/cJSON.hpp"

class last_seen_http_app_t : public http_app_t {
public:
    explicit last_seen_http_app_t(last_seen_tracker_t *last_seen_tracker);
    http_res_t handle(const http_req_t &);

private:
    last_seen_tracker_t *last_seen_tracker;
};

#endif /* CLUSTERING_ADMINISTRATION_HTTP_LAST_SEEN_APP_HPP_ */
