import { useDispatch, useSelector, useStore } from 'react-redux'
import type { RootState } from './reducer'
import type { AppDispatch, AppStore } from './store'

export const useAppDispatch = useDispatch.withTypes<AppDispatch>()
export const useAppSelector = useSelector.withTypes<RootState>()
export const useAppStore = useStore.withTypes<AppStore>()
