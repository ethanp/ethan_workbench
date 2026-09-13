/// shelf_io buffers streamed bodies by default; that stalls SSE on the phone.
abstract final class DeployHttpSse() {
  static const headers = {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    'Connection': 'keep-alive',
  };

  static const context = {'shelf.io.buffer_output': false};
}
