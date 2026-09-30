export function hasDuneWatchReadyMessage(output) {
  return output.includes("Success, waiting for filesystem changes")
}
