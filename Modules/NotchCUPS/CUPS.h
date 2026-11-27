#include <cups/cups.h>

static inline ipp_t *notchCreatePrintQueueRequest(void) {
    ipp_t *request = ippNewRequest(IPP_OP_GET_JOBS);
    if (!request) {
        return NULL;
    }

    const char *attributes[] = {
        "job-id", "job-state", "job-impressions", "job-impressions-completed",
        "job-media-sheets", "job-media-sheets-completed"
    };
    ippAddString(request, IPP_TAG_OPERATION, IPP_TAG_URI, "printer-uri", NULL, "ipp://localhost/");
    ippAddString(request, IPP_TAG_OPERATION, IPP_TAG_NAME, "requesting-user-name", NULL, cupsUser());
    ippAddString(request, IPP_TAG_OPERATION, IPP_TAG_KEYWORD, "which-jobs", NULL, "not-completed");
    ippAddBoolean(request, IPP_TAG_OPERATION, "my-jobs", 1);
    ippAddStrings(request, IPP_TAG_OPERATION, IPP_TAG_KEYWORD, "requested-attributes",
                  sizeof(attributes) / sizeof(attributes[0]), NULL, attributes);
    return request;
}
